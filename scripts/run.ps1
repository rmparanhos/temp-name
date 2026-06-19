# Inicia o companion (blob + bandeja). Deixe esta janela aberta enquanto usa.
Set-Location (Split-Path $PSScriptRoot -Parent)

# Se ja esta compilado, abre o .exe direto (nao precisa de toolchain/compilador).
$exe = "target\release\companiond.exe"
if (Test-Path $exe) {
    & $exe
} else {
    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        $env:Path += ";$env:USERPROFILE\.cargo\bin"
    }
    cargo run --release -p companiond
}
