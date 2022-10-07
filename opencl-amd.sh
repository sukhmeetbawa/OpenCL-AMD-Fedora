#!/usr/bin/env bash
set -e

rootCheck()
{
    if [[ $UID -ne 0 ]]; then
        sudo -p 'Restarting as Root, Password: ' bash $0 "$@"
        exit $?
    fi
}
installPortableGL()
{
    echo "Downloading Dependencies"
    dnf install cpio
    echo "Enabling Proprietary AMD Repository"
	sed -i 's/enabled=0/enabled=1/g' /etc/yum.repos.d/amdgpu-proprietary.repo
    echo "Downloading Drivers"
    dnf install --downloadonly libegl-amdgpu-pro libgl-amdgpu-pro libgl-amdgpu-pro-dri libgl-amdgpu-pro-ext libglapi-amdgpu-pro libgles-amdgpu-pro --destdir=/tmp/amdDriverCache -y
    cd /tmp/amdDriverCache
    for rpm in *rpm; do
    	rpm2cpio "$rpm" | cpio -idm
    done
    mkdir -p /home/$SUDO_USER/.amdgpu-progl-portable
    chmod -R 755 /home/$SUDO_USER/.amdgpu-progl-portable
    cp -a /tmp/amdDriverCache/etc /tmp/amdDriverCache/opt /tmp/amdDriverCache/usr /home/$SUDO_USER/.amdgpu-progl-portable
    echo "ProGL Installed for User"
    echo "Clean Download Cache"
    rm -rf /tmp/amdDriverCache
}

patchResolve()
{
	isCLInstalled=$(dnf repolist enabled | grep sukhmeet:amdgpu-core | wc -c)
	if [[ $isCLInstalled != 0 ]]; then
		echo "Proprietary OpenCL is installed, proceeding to Resolve patching..."
	else
		echo "OpenCL has not been installed yet. Please select options 1 or 2..."
		menu
		return
	fi
	if [[ -d /home/$SUDO_USER/.amdgpu-progl-portable ]]; then
		echo "Portable ProGL is installed, proceeding to Resolve patching..."
	else
		echo "Portable ProGL has not been installed yet, installing before patching Resolve..."
		installPortableGL
	fi
    resolveBinary=/opt/resolve/bin/resolve
    desktopFile=/usr/share/applications/com.blackmagicdesign.resolve.desktop

    if [ -f "$resolveBinary" ]; then
        echo "Davinci Resolve appears to be installed"
        if [[ -f "$desktopFile" ]]; then
            echo "Backing up .desktop file to $desktopFile.bak"
            sudo cp $desktopFile $desktopFile.bak
            echo "Patching .desktop file at $desktopFile"
            sed -i 's|Exec=.*|Exec=bash -c "LD_LIBRARY_PATH=\"/home/'$SUDO_USER'/.amdgpu-progl-portable/opt/amdgpu-pro/lib64:\${LD_LIBRARY_PATH}\" LIBGL_DRIVERS_PATH=\"/home/'$SUDO_USER'/.amdgpu-progl-portable/usr/lib64/dri/\" dri_driver=\"amdgpu\" QT_DEVICE_PIXEL_RATIO=1 QT_AUTO_SCREEN_SCALE_FACTOR=false /opt/resolve/bin/resolve"|g' '/usr/share/applications/com.blackmagicdesign.resolve.desktop'
            echo "Patching Davinci Resolve audio delay bug..."
            sudo dnf install alsa-plugins-pulseaudio
            echo "Done!"
	while true; do
            read -p "Do you want to patch Resolve for Hi-DPI scaling? [y/n]: " yn
            case $yn in
                [Yy]* ) echo "Patching for hidpi"; sudo sed -i 's|QT_DEVICE_PIXEL_RATIO=1 QT_AUTO_SCREEN_SCALE_FACTOR=false|QT_DEVICE_PIXEL_RATIO=2 QT_AUTO_SCREEN_SCALE_FACTOR=true|g' /usr/share/applications/com.blackmagicdesign.resolve.desktop; break;;
                [Nn]* ) echo "Not patching"; exit;;
                * ) echo "Please answer y or n";;
            esac
        done
        else
            echo "Could not locate Davinci Resolve desktop file at $desktopFile. This is not a supported configuration."
        fi
    else
        echo "Error: $resolveBinary was not found. Has Davinci Resolve been installed yet?"
        if [[ -f "$desktopFile" ]]; then
            echo "Found Desktop file for Davinci Resolve at $desktopFile, but the Resolve binary was not found. This is not a supported configuration"
        else
            echo "Error: Could not locate Davinci Resolve binary at $desktopFile. Has Davinci Resolve been installed yet?"
        fi
    fi
}

installLatestRepo()
{
    if [ $(ls -l /etc/yum.repos.d/ | grep -v rpmsave | grep amdgpu.repo | wc -l) == 0 ]; then
        RPM=$(curl --silent http://repo.radeon.com/amdgpu-install/latest/rhel/${latestRHEL}/ | grep rpm | awk 'BEGIN{FS=">"} {print $2}' | awk 'BEGIN{FS="<"} {print $1}')
        echo "Installing amdgpu-install"
        dnf install http://repo.radeon.com/amdgpu-install/latest/rhel/${latestRHEL}/${RPM} -y
        echo "Fixing Repositories"
        sed -i 's/$amdgpudistro/'$latestRHEL'/g' /etc/yum.repos.d/amdgpu*.repo
        sed -i 's/'$latestDriverVersion'/latest/g' /etc/yum.repos.d/amdgpu*.repo
	sed -i 's|rhel[0-9].*/*/|yum/latest/|g' /etc/yum.repos.d/rocm.repo
	sed -i 's/enabled=0/enable=1/g' /etc/yum.repos.d/rocm.repo
    fi
}

installLatestOpenCL()
{
    installLatestRepo
    if  [ "$(dnf list installed | grep mesa-libOpenCL | wc -l)" == 1 ]; then
        echo "Removing Mesa OpenCL"
        dnf remove mesa-libOpenCL -y
    fi
    echo "Installing Workaroud Package"
    dnf copr enable sukhmeet/amdgpu-core-shim -y &> /dev/null
    dnf install amdgpu-core-shim -y
    echo "Installing OpenCL Runtime"
    dnf install rocm-opencl -y
}

installLegacyOpenCL()
{
		echo "Downloading Necessary Files"
		wget -q --show-progress --referer=https://www.amd.com/en/support/kb/release-notes/rn-amdgpu-unified-linux-21-30 https://drivers.amd.com/drivers/linux/amdgpu-pro-21.30-1290604-rhel-8.4.tar.xz
		echo "Installing Workaround Package"
		dnf copr enable sukhmeet/amdgpu-core-shim -y &> /dev/null
		dnf install amdgpu-core-shim -y
		echo "Extracting Files"
		tar -xvf $(pwd)/*amdgpu-pro-21.30*.xz
		echo "Setting up Local Repository"
		mkdir -p /var/local/amdgpu
		cp -r $(pwd)/amdgpu-pro-21.30-*-rhel-8.4/* /var/local/amdgpu/
		rm -f /etc/yum.repos.d/amdgpu.repo
		cat > /etc/yum.repos.d/amdgpu.repo << EOF
[amdgpu]
name=AMDGPU Packages
baseurl=file:///var/local/amdgpu/
enabled=1
skip_if_unavailable=1
gpgcheck=0
cost=500
metadata_expire=300
EOF
		echo "Installing Another Workaround Package"
		dnf copr enable rmnscnce/amdgpu-pro-shims -y &> /dev/null
		dnf install amdgpu-pro-shims -y
		echo "Installing OpenCL"
		dnf install opencl-rocr-amdgpu-pro rocm-device-libs-amdgpu-pro hsa-runtime-rocr-amdgpu hsakmt-roct-amdgpu hip-rocr-amdgpu-pro comgr-amdgpu-pro opencl-orca-amdgpu-pro-icd libdrm-amdgpu-common ocl-icd-amdgpu-pro opencl-rocr-amdgpu-pro amdgpu-pro-core -y
		echo "Installation Successful"
}

installLatestHIP(){
    installLatestRepo
    dnf copr enable sukhmeet/amdgpu-core-shim -y &> /dev/null
    dnf install platform-python-shim -y
    echo "Installing HIP Runtime"
    sudo dnf install amdgpu-core-shim hip-runtime-amd --exclude=rocm-llvm -y
}

yesno()
{
	echo "A local repository will setup"
	while true; do
    	read -p "Do you wish to continue? [y/n]: " yn
	    case $yn in
    	    [Yy]* ) installLegacyOpenCL; break;;
    	    [Nn]* ) exit;;
    	    * ) echo "Please answer y or n";;
    	esac
	done
}

uninstallOpenCL()
{
	echo "Uninstalling Packages"
    dnf remove rocm-opencl rocm-opencl-runtime libdrm-amdgpu amdgpu-core-shim amdgpu-install opencl-rocr-amdgpu-pro rocm-device-libs-amdgpu-pro hsa-runtime-rocr-amdgpu hsakmt-roct-amdgpu hip-rocr-amdgpu-pro comgr-amdgpu-pro opencl-orca-amdgpu-pro-icd libdrm-amdgpu-common ocl-icd-amdgpu-pro opencl-rocr-amdgpu-pro amdgpu-pro-core amdgpu-pro-shims -y
	echo "Checking for Local Repository"
    if [ "$(ls /var/local/ | grep amdgpu | wc -l)" == 1 ]; then
    	echo "Removing Local Repository"
	    rm -rf /var/local/amdgpu
	fi
	if [ "$(ls /etc/yum.repos.d/ | grep amdgpu.repo | wc -l)" -gt 0 ]; then
		sudo rm -rf /etc/yum.repos.d/amdgpu.repo
	fi
}

uninstallProGL()
{
	desktopFile=/usr/share/applications/com.blackmagicdesign.resolve.desktop
	rm -rf /home/$SUDO_USER/.amdgpu-progl-portable
	if [[ -f $desktopFile.bak ]]; then
		echo "Restoring Davinci Resolve .desktop file..."
		sudo rm $desktopFile
		sudo cp $desktopFile.bak $desktopFile && sudo chmod 755 $desktopFile && sudo rm $desktopFile.bak
	fi
}

uninstallHIP()
{
	echo "Uninstalling Packages"
	dnf remove hip-runtime-amd -y
}
menu()
{
	printf "\nLegacy Drivers are are required for Arctic Islands/Polaris\n"
	printf "Latest Drivers work with Vega and Above\n\n"
    PS3='Enter Option Number: '
    options=("Install-OpenCL-Latest" "Install-OpenCL-Legacy" "Install-HIP-Runtime" "Install-Portable-ProGL" "Patch-Davinci-Resolve" "Uninstall-OpenCL" "Uninstall-ProGL" "Uninstall-HIP-Runtime" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "Install-OpenCL-Latest")
                echo "Installing Latest OpenCL Stack"
                installLatestOpenCL
                echo "Install Successful"
                break
                ;;
             "Install-OpenCL-Legacy")
             	echo "Installing Legacy OpenCL Stack"
             	yesno
             	break
                ;;
            "Install-Portable-ProGL")
                echo "Installing Portable ProGL"
		installPortableGL
                break
                ;;
            "Patch-Davinci-Resolve")
                echo "Patching Resolve .desktop file"
		patchResolve
                break
                ;;
            "Install-HIP-Runtime")
                echo "(WIP) For Testing Purposes"
                installLatestHIP
                break
                ;;
            "Uninstall-OpenCL")
                echo "Uninstalling OpenCL Stack"
                uninstallOpenCL
                echo "Uninstall Successful"
                break
                ;;
            "Uninstall-ProGL")
                echo "Uninstalling Portable ProGL Stack"
                uninstallProGL
                echo "Uninstall Successful"
                break
                ;;
	   "Uninstall-HIP-Runtime")
		echo "Uninstalling HIP Runtime"
		uninstallHIP
		echo "Uninstall Successful"
		break
		;;
            "Quit")
                break
                ;;
            *) echo "Invalid Option $REPLY";;
        esac
    done

}
#Driver Code
rootCheck
# Environment Variables Required
latestRHEL="$(echo $(curl http://repo.radeon.com/amdgpu-install/latest/rhel/ --silent | grep href | tail -1 | sed 's/.*\/">//; s/\/<\/a.*//'))"
latestDriverVersion="$(echo $(curl http://repo.radeon.com/amdgpu-install/ --silent | grep href | tail -2 | head -1 | sed 's/.*\/">//; s/\/<\/a.*//'))"
menu
