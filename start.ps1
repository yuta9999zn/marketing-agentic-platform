# MarketingOS — khoi dong tren Windows PowerShell
# Cach dung:  .\start.ps1            (migrate + seed neu can, roi start server)
#            .\start.ps1 -Shell      (mo shell da set PATH dung, go lenh tuy y)

param([switch]$Shell)

# Dan Node 'bundle' shim len truoc trong PATH -> Bundler Ruby thang
$env:Path = "C:\Ruby33-x64\bin;" + $env:Path

# Kiem tra bundle goi dung Bundler Ruby
$bundlePath = (Get-Command bundle -ErrorAction SilentlyContinue).Source
if ($bundlePath -notlike "*Ruby*") {
    Write-Host "ERROR: van go sai bundle tai: $bundlePath" -ForegroundColor Red
    Write-Host "Dung: C:\Ruby33-x64\bin\bundle.bat exec rails server"
    exit 1
}

if ($Shell) {
    Write-Host "PATH da chuan. Go lenh binh thuong, vi du:" -ForegroundColor Green
    Write-Host "  bundle exec rails db:migrate"
    Write-Host "  bundle exec rails db:seed"
    Write-Host "  bundle exec rails server"
    return
}

Set-Location $PSScriptRoot

Write-Host "== MarketingOS ==" -ForegroundColor Cyan
bundle exec rails db:migrate
if ($LASTEXITCODE -ne 0) { Write-Host "Migrate that bai." -ForegroundColor Red; exit 1 }

# Seed chi khi chua co du lieu demo
$seeded = bundle exec rails runner "print Organization.exists?"
if ($seeded -ne "true") {
    bundle exec rails db:seed
}

Write-Host ""
Write-Host "Server: http://localhost:3000  (Ctrl+C de tat)" -ForegroundColor Cyan
Write-Host "Demo login: owner@demo.vn / password123"
Write-Host ""
bundle exec rails server
