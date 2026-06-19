# =====================================================================
#  CHRIS - instalacao automatica para Windows (1 clique)
#
#  Funciona em DOIS cenarios, sem voce escolher nada:
#   * Se voce JA tem o linker da MSVC (link.exe) -> usa ele.
#   * Se NAO tem (e nao tem admin pra instalar) -> usa a toolchain GNU +
#     um MinGW-w64 PORTATIL baixado na sua pasta de usuario. Sem admin,
#     sem link.exe.
#
#  No fim, compila e ja abre o CHRIS. Rode com duplo-clique no setup.bat.
# =====================================================================

$ErrorActionPreference = "Continue"
function Have($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# O linker da MSVC (link.exe) esta disponivel? (via vswhere)
function Test-MsvcLinker {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) { return $false }
    $p = & $vswhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    return [bool]$p
}

# Baixa um MinGW-w64 PORTATIL (compilador GNU: gcc + windres) para a pasta do
# usuario e coloca no PATH. Nao precisa de admin. Devolve a pasta 'bin'.
function Install-PortableMingw {
    $root = Join-Path $env:USERPROFILE ".chris\mingw"
    $existing = Get-ChildItem -Path $root -Recurse -Filter "gcc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) { return (Split-Path $existing.FullName) }

    Write-Host "-> Baixando o compilador MinGW-w64 (portatil, ~100 MB). So uma vez..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $root | Out-Null

    # Descobre o zip mais recente do WinLibs (UCRT, 64-bit, sem LLVM = menor).
    $url = $null
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/brechtsanders/winlibs_mingw/releases/latest" `
            -Headers @{ "User-Agent" = "chris-setup" }
        $asset = $rel.assets | Where-Object {
            $_.name -match "x86_64-posix-seh-gcc" -and $_.name -match "ucrt" -and `
            $_.name -like "*.zip" -and $_.name -notmatch "llvm"
        } | Select-Object -First 1
        if (-not $asset) {
            $asset = $rel.assets | Where-Object { $_.name -match "x86_64" -and $_.name -match "ucrt" -and $_.name -like "*.zip" } | Select-Object -First 1
        }
        if ($asset) { $url = $asset.browser_download_url }
    } catch { }

    if (-not $url) {
        Write-Host "Nao consegui descobrir o link do MinGW (sem internet?)." -ForegroundColor Red
        return $null
    }

    $zip = Join-Path $env:TEMP "winlibs-mingw.zip"
    Write-Host "   $url"
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Write-Host "-> Descompactando (demora um pouco)..." -ForegroundColor Yellow
    Expand-Archive -Path $zip -DestinationPath $root -Force
    Remove-Item $zip -ErrorAction SilentlyContinue

    $gcc = Get-ChildItem -Path $root -Recurse -Filter "gcc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($gcc) { return (Split-Path $gcc.FullName) }
    return $null
}

# Adiciona uma pasta ao PATH desta sessao e, de forma persistente, ao PATH do
# usuario (sem admin) -- assim o run.bat e futuras recompilacoes funcionam.
function Add-ToPath($dir) {
    if (-not $dir) { return }
    if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$dir;$env:Path" }
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (($userPath -split ';') -notcontains $dir) {
        [Environment]::SetEnvironmentVariable("Path", "$dir;$userPath", "User")
    }
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

# ---- 1. WebView2 (a 'tela' do app; normalmente ja existe) ----
Write-Host "-> WebView2 Runtime..." -ForegroundColor Yellow
winget install --id Microsoft.EdgeWebView2Runtime -e `
    --accept-package-agreements --accept-source-agreements 2>$null | Out-Null

# ---- 2. Rust (rustup instala no seu usuario, sem admin) ----
if (-not (Have cargo)) {
    Write-Host "-> Rust (rustup)..." -ForegroundColor Yellow
    winget install --id Rustlang.Rustup -e `
        --accept-package-agreements --accept-source-agreements 2>$null
    $env:Path += ";$env:USERPROFILE\.cargo\bin"
}
if (-not (Have cargo)) {
    Write-Host ""
    Write-Host "Rust foi instalado, mas o 'cargo' ainda nao esta no PATH desta janela." -ForegroundColor Yellow
    Write-Host "FECHE esta janela e rode o setup.bat de novo para concluir."
    Read-Host "Enter para sair"; exit 1
}

# ---- 3. Escolhe a toolchain: MSVC se tiver, senao GNU + MinGW portatil ----
if (Test-MsvcLinker) {
    Write-Host "-> Linker MSVC encontrado. Usando a toolchain MSVC." -ForegroundColor Green
    rustup default stable-msvc 2>$null | Out-Null
} else {
    Write-Host "-> Sem linker MSVC (e sem admin pra instalar). Usando GNU." -ForegroundColor Green
    rustup toolchain install stable-x86_64-pc-windows-gnu 2>$null | Out-Null
    rustup default stable-x86_64-pc-windows-gnu 2>$null | Out-Null

    # garante o compilador GNU (gcc + windres). O Tauri precisa do windres
    # pro icone, e uma dependencia precisa do gcc.
    if (-not (Have gcc) -or -not (Have windres)) {
        $bin = Install-PortableMingw
        if (-not $bin) {
            Write-Host "Nao foi possivel preparar o compilador MinGW." -ForegroundColor Red
            Read-Host "Enter para sair"; exit 1
        }
        Add-ToPath $bin
    }
    if (-not (Have gcc)) {
        Write-Host "O compilador GNU (gcc) ainda nao esta no PATH." -ForegroundColor Red
        Read-Host "Enter para sair"; exit 1
    }
}

# ---- 4. Compila o CHRIS ----
Set-Location (Split-Path $PSScriptRoot -Parent)
Write-Host ""
Write-Host "-> Compilando o CHRIS (a primeira vez demora alguns minutos)..." -ForegroundColor Yellow
cargo build --release -p chris-cli
if ($LASTEXITCODE -ne 0) { Write-Host "Falha ao compilar a CLI." -ForegroundColor Red; Read-Host "Enter para sair"; exit 1 }
cargo build --release -p companiond
if ($LASTEXITCODE -ne 0) { Write-Host "Falha ao compilar o app." -ForegroundColor Red; Read-Host "Enter para sair"; exit 1 }

Write-Host ""
Write-Host "===== Pronto! Iniciando o CHRIS... =====" -ForegroundColor Green
Write-Host "(Para ligar num projeto: rode connect.bat dentro da pasta do projeto.)"
Write-Host "(Para iniciar de novo no futuro: duplo-clique em run.bat.)"
Write-Host ""

# ---- 5. Roda (install + run num clique so) ----
$exe = Join-Path (Split-Path $PSScriptRoot -Parent) "target\release\companiond.exe"
if (Test-Path $exe) { Start-Process $exe } else { & (Join-Path $PSScriptRoot "run.ps1") }
