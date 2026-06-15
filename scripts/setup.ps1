# =====================================================================
#  CHRIS - instalacao automatica para Windows (1 clique)
#  Instala Rust + C++ Build Tools (com o linker) + WebView2, compila e
#  inicia o CHRIS. Rode com duplo-clique no setup.bat.
# =====================================================================

$ErrorActionPreference = "Continue"
function Have($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# Confere se o linker da MSVC (link.exe) ja esta disponivel, via vswhere.
# E o que o Rust precisa; se faltar, o build quebra com "linker link.exe not found".
function Test-Linker {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $false }
    $path = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    return [bool]$path
}

Write-Host ""
Write-Host "===== Instalacao do CHRIS =====" -ForegroundColor Cyan
Write-Host ""

# ---- 0. winget disponivel? ----
if (-not (Have winget)) {
    Write-Host "ERRO: 'winget' nao encontrado." -ForegroundColor Red
    Write-Host "Abra a Microsoft Store, instale/atualize o 'App Installer' e rode de novo."
    Read-Host "Enter para sair"; exit 1
}

# ---- 1. C++ Build Tools (necessario pro Rust MSVC e pro Tauri) ----
# IMPORTANTE: usamos --force E o workload C++ (VCTools) + --includeRecommended
# (que traz o Windows SDK). O --force garante que o workload seja ADICIONADO
# mesmo que o "Build Tools" ja exista sem ele -- esse era o motivo do erro
# "linker link.exe not found".
if (Test-Linker) {
    Write-Host "-> C++ Build Tools (linker) ja presente. Pulando." -ForegroundColor Green
} else {
    Write-Host "-> Instalando C++ Build Tools + Windows SDK (pode demorar bastante)..." -ForegroundColor Yellow
    Write-Host "   (Se aparecer um pedido de permissao do Windows, aceite.)"
    winget install --id Microsoft.VisualStudio.2022.BuildTools -e --force `
        --accept-package-agreements --accept-source-agreements `
        --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended" 2>$null
}

# ---- 2. WebView2 (a 'tela' do app; normalmente ja existe) ----
Write-Host "-> WebView2 Runtime..." -ForegroundColor Yellow
winget install --id Microsoft.EdgeWebView2Runtime -e `
    --accept-package-agreements --accept-source-agreements 2>$null | Out-Null

# ---- 3. Rust ----
if (-not (Have cargo)) {
    Write-Host "-> Rust..." -ForegroundColor Yellow
    winget install --id Rustlang.Rustup -e `
        --accept-package-agreements --accept-source-agreements 2>$null
    $env:Path += ";$env:USERPROFILE\.cargo\bin"   # deixa o cargo acessivel agora
}
if (Have rustup) { rustup default stable-msvc 2>$null | Out-Null }

if (-not (Have cargo)) {
    Write-Host ""
    Write-Host "Rust foi instalado, mas o 'cargo' ainda nao esta no PATH desta janela." -ForegroundColor Yellow
    Write-Host "FECHE esta janela e rode o setup.bat de novo para concluir."
    Read-Host "Enter para sair"; exit 1
}

# ---- 4. Conferir o linker ANTES de compilar (erro claro em vez de cripto) ----
if (-not (Test-Linker)) {
    Write-Host ""
    Write-Host "ATENCAO: o linker da MSVC (link.exe) ainda nao foi encontrado." -ForegroundColor Red
    Write-Host "Isso costuma acontecer quando o 'Build Tools' existe mas sem o C++." -ForegroundColor Red
    Write-Host ""
    Write-Host "Conserto rapido:" -ForegroundColor Yellow
    Write-Host "  1. Abra o 'Visual Studio Installer'."
    Write-Host "  2. No Build Tools 2022, clique 'Modify'."
    Write-Host "  3. Marque o workload 'Desktop development with C++' e instale."
    Write-Host "  4. Rode o setup.bat de novo."
    Write-Host ""
    Write-Host "(Pode ser preciso permissao de administrador: clique com o botao"
    Write-Host " direito no setup.bat -> 'Executar como administrador'.)"
    Read-Host "Enter para sair"; exit 1
}

# ---- 5. Compila o CHRIS ----
Set-Location (Split-Path $PSScriptRoot -Parent)   # vai para a raiz do projeto
Write-Host ""
Write-Host "-> Compilando o CHRIS (a primeira vez demora alguns minutos)..." -ForegroundColor Yellow
cargo build --release -p chris-cli
if ($LASTEXITCODE -ne 0) { Write-Host "Falha ao compilar a CLI." -ForegroundColor Red; Read-Host "Enter para sair"; exit 1 }
cargo build --release -p companiond
if ($LASTEXITCODE -ne 0) { Write-Host "Falha ao compilar o app." -ForegroundColor Red; Read-Host "Enter para sair"; exit 1 }

Write-Host ""
Write-Host "===== Pronto! Iniciando o CHRIS... =====" -ForegroundColor Green
Write-Host "(Para ligar num projeto depois: rode connect.bat dentro da pasta do projeto.)"
Write-Host "(Para iniciar de novo no futuro: duplo-clique em run.bat.)"
Write-Host ""

# ---- 6. Roda (install + run num clique so) ----
$exe = Join-Path (Split-Path $PSScriptRoot -Parent) "target\release\companiond.exe"
if (Test-Path $exe) { Start-Process $exe } else { & (Join-Path $PSScriptRoot "run.ps1") }
