# TrendRadar GitHub Actions 一键部署脚本
# 使用前请先执行: gh auth login

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot
$RepoName = "TrendRadar-practice"

# 刷新 PATH
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')

Write-Host "=== TrendRadar GitHub Actions 部署 ===" -ForegroundColor Cyan

# 1. 检查 gh 登录
$auth = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[错误] 尚未登录 GitHub。请先运行:" -ForegroundColor Red
    Write-Host "  gh auth login" -ForegroundColor Yellow
    Write-Host "`n按提示选择: GitHub.com -> HTTPS -> Login with a web browser" -ForegroundColor Gray
    exit 1
}
$username = (gh api user --jq .login)
Write-Host "[OK] 已登录 GitHub: $username" -ForegroundColor Green

# 2. 读取邮件配置
$secretsFile = Join-Path $RepoRoot "secrets.local.env"
if (Test-Path $secretsFile) {
    Write-Host "[OK] 读取 secrets.local.env" -ForegroundColor Green
    Get-Content $secretsFile | ForEach-Object {
        if ($_ -match '^\s*([^#=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
        }
    }
}

$emailFrom = $env:EMAIL_FROM
$emailPassword = $env:EMAIL_PASSWORD
$emailTo = $env:EMAIL_TO

if (-not $emailFrom -or -not $emailPassword -or -not $emailTo) {
    Write-Host "`n请填写邮件配置（QQ/163 邮箱授权码，不是登录密码）:" -ForegroundColor Yellow
    if (-not $emailFrom) { $emailFrom = Read-Host "发件邮箱 EMAIL_FROM" }
    if (-not $emailPassword) { $emailPassword = Read-Host "邮箱授权码 EMAIL_PASSWORD" -AsSecureString; $emailPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($emailPassword)) }
    if (-not $emailTo) { $emailTo = Read-Host "收件邮箱 EMAIL_TO（可与发件相同）" }
}

# 3. 初始化 git 并推送
Set-Location $RepoRoot
if (-not (Test-Path ".git")) {
    git init
    git branch -M master
}
git add -A
$status = git status --porcelain
if ($status) {
    git commit -m "TrendRadar practice: email push setup"
}

# 检查远程仓库
$remoteUrl = "https://github.com/$username/$RepoName.git"
$repoExists = gh repo view "$username/$RepoName" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[创建仓库] $username/$RepoName ..." -ForegroundColor Cyan
    gh repo create $RepoName --public --source=. --remote=origin --push
} else {
    Write-Host "`n[仓库已存在] $username/$RepoName，推送更新..." -ForegroundColor Cyan
    git remote remove origin 2>$null
    git remote add origin $remoteUrl
    git push -u origin master --force
}

# 4. 配置 Secrets
Write-Host "`n[配置 Secrets] ..." -ForegroundColor Cyan
$emailFrom | gh secret set EMAIL_FROM
$emailPassword | gh secret set EMAIL_PASSWORD
$emailTo | gh secret set EMAIL_TO
Write-Host "[OK] EMAIL_FROM / EMAIL_PASSWORD / EMAIL_TO 已设置" -ForegroundColor Green

# 5. 触发 workflow
Write-Host "`n[触发测试] Get Hot News workflow ..." -ForegroundColor Cyan
gh workflow run "Get Hot News" --repo "$username/$RepoName"
Start-Sleep -Seconds 3
$runUrl = gh run list --repo "$username/$RepoName" --workflow "Get Hot News" --limit 1 --json url --jq '.[0].url'
Write-Host "`n=== 部署完成 ===" -ForegroundColor Green
Write-Host "仓库: https://github.com/$username/$RepoName" -ForegroundColor White
if ($runUrl) { Write-Host "运行状态: $runUrl" -ForegroundColor White }
Write-Host "`n约 2-5 分钟后查收邮件。每 7 天需在 Actions 运行 Check In 续期。" -ForegroundColor Gray
