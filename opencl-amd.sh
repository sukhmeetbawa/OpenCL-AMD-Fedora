#!/usr/bin/env bash
set -e

rootCheck()
{
    if [[ $UID -ne 0 ]]; then
        sudo -p 'Restarting as Root, Password: ' bash $0 "$@"
        exit $?
    fi
}

getVersions()
{
	#Check the repo for the latest version of the driver and save it as a variable
	latestDriverVersion=$(curl --silent http://repo.radeon.com/amdgpu-install/ | grep href | tail -2 | head -1 | sed 's/.*\/">//; s/\/<\/a.*//')
	#Check the repo for the latest supported RHEL version and save it as a variable
	latestRHEL=$(curl --silent http://repo.radeon.com/amdgpu-install/latest/rhel/ | grep href | tail -1 | sed 's/.*\/">//; s/\/<\/a.*//')
}

installLatestRepo()
{
    getVersions
    if [ $(ls -l /etc/yum.repos.d/ | grep -v rpmsave | grep amdgpu.repo | wc -l) == 0 ]; then
        RPM=$(curl --silent http://repo.radeon.com/amdgpu-install/latest/rhel/${latestRHEL}/ | grep rpm | awk 'BEGIN{FS=">"} {print $2}' | awk 'BEGIN{FS="<"} {print $1}')
        echo "Installing amdgpu-install"
        dnf install http://repo.radeon.com/amdgpu-install/latest/rhel/${latestRHEL}/${RPM} -y
        echo "Fixing Repositories"
        sed -i 's/$amdgpudistro/'$latestRHEL'/g' /etc/yum.repos.d/amdgpu*.repo
        sed -i 's/'$latestDriverVersion'/latest/g' /etc/yum.repos.d/amdgpu*.repo
	
        #The order of operations between thess two expressions is 
	#important because I don't know without looking at the file it's editing if it will encounter a space or a newline. 
	#That's why both of these exist; I couldn't figure out how to do it all in one sed expression.
	#Not sure of a cleaner way to do this unfortunately. Feel free to improve this.
	sed -i 's|rhel[0-9].*/*[ ]|yum/latest |g' /etc/yum.repos.d/rocm.repo
	sed -i 's|rhel[0-9].*/*|yum/latest|g' /etc/yum.repos.d/rocm.repo
	
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
    sudo dnf install rocm-hip-runtime -y
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
    dnf remove rocm-opencl ocl-icd rocm-opencl-runtime libdrm-amdgpu amdgpu-core-shim amdgpu-install opencl-rocr-amdgpu-pro rocm-device-libs-amdgpu-pro hsa-runtime-rocr-amdgpu hsakmt-roct-amdgpu hip-rocr-amdgpu-pro comgr-amdgpu-pro opencl-orca-amdgpu-pro-icd libdrm-amdgpu-common ocl-icd-amdgpu-pro opencl-rocr-amdgpu-pro amdgpu-pro-core amdgpu-pro-shims rocm-hip-runtime -y
	echo "Checking for Local Repository"
    if [ "$(ls /var/local/ | grep amdgpu | wc -l)" == 1 ]; then
    	echo "Removing Local Repository"
	    rm -rf /var/local/amdgpu
	fi
	if [ "$(ls /etc/yum.repos.d/ | grep amdgpu.repo | wc -l)" -gt 0 ]; then
		sudo rm -rf /etc/yum.repos.d/amdgpu.repo
	fi
}

menu()
{
	echo "Legacy Drivers are are required for Arctic Islands/Polaris"
	echo "Latest Drivers work with Vega and Above"
    PS3='Enter Option Number: '
    options=("Install-OpenCL-Latest" "Install-OpenCL-Legacy" "Install-HIP-Latest" "Uninstall" "Quit")
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
            "Install-HIP-Latest")
                echo "(WIP) For Testing Purposes"
                installLatestHIP
                break
                ;;
            "Uninstall")
                echo "Uninstalling OpenCL Stack"
                uninstallOpenCL
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
menu
