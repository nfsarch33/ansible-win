#at top of script
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
function Install-Chocolatey {
    Install-PackageProvider Chocolatey -scope CurrentUser
    Set-PackageSource -name Chocolatey -trusted
}
function Install-ChocolateyBase {
    try {
        $testchoco = choco -v
        # Install Chocolatey if not found
        if ((-not($testchoco)) -or ($testchoco.length -gt 10)) {
            Install-Chocolatey
        }
        else {
            Write-Output "Chocolatey Version $testchoco is already installed"
        }
    }
    catch {
        Write-Error $_.Exception
    }
}
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Set-ExecutionPolicy AllSigned
# Install-Scoop
Install-ChocolateyBase
Write-Output "Installing Chocolatey packages"
# The following enables allowGlobalConfirmation - install without confirmation prompts.
choco feature enable -n=allowGlobalConfirmation
# Upgrade
choco upgrade chocolatey

# Basic utilities
choco install 7zip.install -y
choco install 7zip.commandline -y
choco install 7zip.portable -y
choco install open-shell -y
choco install putty.portable -y

# Browsers
choco install chrome -y
choco install firefox -y

# Essential runtimes
choco install VCredist-All -y

# Gaming platforms
choco install steam -y
choco install battlenet -y

# NVIDIA drivers and software
choco install nvidia -y
choco install nvidia-experience -y

# Communication and social
choco install telegram.install -y
choco install skype -y
choco install discord -y
choco install zoom -y
choco install microsoft-teams -y
choco install slack -y

# Audio and Video
choco install vlc -y
choco install obs-studio -y
choco install audacity -y

# Utilities
choco install Rufus -y
choco install Putty -y
choco install winscp -y
choco install NotepadPlusPlus.install -y
choco install adobereader -y
choco install xnviewmp -y
choco install expressvpn -y
choco install virtualbox -y
choco install xyplorer -y
choco install internet-download-manager -y

# Office Tools
choco install office365homepremium -y

Write-Output "Gaming PC setup complete!"
