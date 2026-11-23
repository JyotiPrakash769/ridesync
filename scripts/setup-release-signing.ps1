# Creates a stable Android release signing key and stores it as GitHub
# Actions secrets for JyotiPrakash769/ridesync. Run it yourself, once:
#   powershell -ExecutionPolicy Bypass -File scripts\setup-release-signing.ps1
# keytool and gh prompt you for every password; nothing is written to the repo.
# KEEP release.jks AND ITS PASSWORD SAFE: losing them means you can never
# ship an update that installs over existing installs.

$ErrorActionPreference = 'Stop'
$repo    = 'JyotiPrakash769/ridesync'
$alias   = 'ridesync'
$keytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
$dir     = Join-Path $env:USERPROFILE '.ridesync-signing'
$jks     = Join-Path $dir 'release.jks'

New-Item -ItemType Directory -Force $dir | Out-Null
if (-not (Test-Path $jks)) {
    Write-Host "Creating $jks - choose a strong password when asked (use the same one for the key)."
    & $keytool -genkeypair -v -keystore $jks -alias $alias -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=RideSync, O=RideSync, C=IN'
    if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }
}

Write-Host "`nUploading secrets to $repo ..."
[Convert]::ToBase64String([IO.File]::ReadAllBytes($jks)) | gh secret set ANDROID_KEYSTORE_BASE64 --repo $repo
gh secret set ANDROID_KEY_ALIAS --repo $repo --body $alias
Write-Host 'Paste the keystore password:'
gh secret set ANDROID_KEYSTORE_PASSWORD --repo $repo
Write-Host 'Paste the key password (same as above unless you chose a different one):'
gh secret set ANDROID_KEY_PASSWORD --repo $repo

Write-Host "`nSHA-1 to use for the Google Maps key restriction:"
& $keytool -list -v -keystore $jks -alias $alias | Select-String 'SHA1:'
Write-Host "Back up $jks somewhere safe (password manager / encrypted drive)."
