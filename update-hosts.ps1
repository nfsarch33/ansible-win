param(
    # Set these to YOUR router/docker-host addresses before running.
    [string]$RouterIp = "192.0.2.1",
    [string]$DockerHostIp = "192.0.2.2"
)

$hostsFile = "C:\Windows\System32\drivers\etc\hosts"

Add-Content -Path $hostsFile -Value "$RouterIp expressvpnrouter.com"
Add-Content -Path $hostsFile -Value "$RouterIp www.expressvpnrouter.com"
Add-Content -Path $hostsFile -Value ""
Add-Content -Path $hostsFile -Value "# Added by Docker Desktop"
Add-Content -Path $hostsFile -Value "$DockerHostIp host.docker.internal"
Add-Content -Path $hostsFile -Value "$DockerHostIp gateway.docker.internal"
Add-Content -Path $hostsFile -Value "127.0.0.1 kubernetes.docker.internal"
Add-Content -Path $hostsFile -Value "# To allow the same kube context to work on the host and the container:"
Add-Content -Path $hostsFile -Value ""
