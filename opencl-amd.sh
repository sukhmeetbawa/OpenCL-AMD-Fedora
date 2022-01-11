#!/usr/bin/env bash
set -e

rootCheck()
{
    if [[ $UID -ne 0 ]]; then
        sudo -p 'Restarting as Root, Password: ' bash $0 "$@"
        exit $?
    fi
}

buildWorkaround()
{
	echo "Checking for Build Dependencies"
	if  [ "$(dnf list installed | grep rpm-build.$(arch) | wc -l)" == 0 ]; then
		echo "Installing Build Dependencies"
        dnf install rpm-build -y 1> /dev/null
        remove=1
    fi
    echo "Building Workaround Package"
    rpmbuild -bb ./amdgpu-core-shim.spec --define "_rpmdir $(pwd)" &> /dev/null
    if  [ "$remove" == 1 ]; then
    	echo "Removing Unneeded Packages"
        dnf remove rpm-build -y 1> /dev/null
    fi
    echo "Installing Workaround Package"
    dnf install $(pwd)/$(arch)/amdgpu-core-shim*.rpm -y 1> /dev/null
}

installLatestOpenCL()
{
	echo "Installing amdgpu-install"
    dnf install http://repo.radeon.com/amdgpu-install/latest/rhel/8.5/amdgpu-install-21.40.40500-1.noarch.rpm -y 1> /dev/null
    echo "Fixing Repositories"
    sed -i 's/$amdgpudistro/8.5/g' /etc/yum.repos.d/amdgpu*.repo
    sed -i 's/21.40/latest/g' /etc/yum.repos.d/amdgpu*.repo
    sed -i 's/4.5/rpm/g' /etc/yum.repos.d/rocm.repo
    sed -i '2s/rpm/Latest/g' /etc/yum.repos.d/rocm.repo
    if  [ "$(dnf list installed | grep mesa-libOpenCL | wc -l)" == 1 ]; then
        echo "Removing Mesa OpenCL"
        dnf remove mesa-libOpenCL -y 1> /dev/null
    fi
    buildWorkaround
    echo "Installing OpenCL Runtime"
    dnf install ocl-icd rocm-opencl-runtime libdrm-amdgpu -y 1> /dev/null
}

installLegacyOpenCL()
{
	if [ "$(ls $(pwd) | grep *amdgpu-pro-21.30*.tar.xz | wc -l)" == 1 ]
	then
		buildWorkaround
		echo "Extracting Files"
		tar -xvf $(pwd)/*amdgpu-pro-21.30*.xz 1> /dev/null
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
		dnf install amdgpu-pro-shims -y 1> /dev/null
		echo "Installing OpenCL"
		dnf install opencl-rocr-amdgpu-pro rocm-device-libs-amdgpu-pro hsa-runtime-rocr-amdgpu hsakmt-roct-amdgpu hip-rocr-amdgpu-pro comgr-amdgpu-pro opencl-orca-amdgpu-pro-icd libdrm-amdgpu-common ocl-icd-amdgpu-pro opencl-rocr-amdgpu-pro amdgpu-pro-core -y 1> /dev/null
		echo "Installation Successful"
	else
		echo "Please Download https://drivers.amd.com/drivers/linux/amdgpu-pro-21.30-1290604-rhel-8.4.tar.xz from this link https://www.amd.com/en/support/kb/release-notes/rn-amdgpu-unified-linux-21-30 and place it in the Parent Directory of this Script"
		exit
	fi
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
    dnf remove rocm-opencl-runtime libdrm-amdgpu amdgpu-core-shim amdgpu-install opencl-rocr-amdgpu-pro rocm-device-libs-amdgpu-pro hsa-runtime-rocr-amdgpu hsakmt-roct-amdgpu hip-rocr-amdgpu-pro comgr-amdgpu-pro opencl-orca-amdgpu-pro-icd libdrm-amdgpu-common ocl-icd-amdgpu-pro opencl-rocr-amdgpu-pro amdgpu-pro-core amdgpu-pro-shims -y 1> /dev/null
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
    options=("Install-Latest" "Install-Legacy" "Uninstall" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "Install-Latest")
                echo "Installing Latest OpenCL Stack"
                installLatestOpenCL
                echo "Install Successful"
                break
                ;;
             "Install-Legacy")
             	echo "Installing Legacy OpenCL Stack"
             	yesno
             	break
                ;;
            "Uninstall")
                echo "Uninstalling OpenCL Stack"
                uninstallOpenCL
                echo "Uninstall Successfull"
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
