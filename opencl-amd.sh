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
	if  [ "$(dnf list installed | grep rpm-build.$(arch) | wc -l)" == 0 ]; then
        dnf install rpm-build -y
        remove=1
        echo remove
    fi
    rpmbuild -bb ./amdgpu-core-shim.spec --define "_rpmdir $(pwd)"
    if  [ "$remove" == 1 ]; then
        dnf remove rpm-build -y
    fi
    dnf install $(pwd)/$(arch)/amdgpu-core-shim*.rpm -y
}

installLatestOpenCL()
{
    dnf install http://repo.radeon.com/amdgpu-install/latest/rhel/8.5/amdgpu-install-21.40.40500-1.noarch.rpm -y
    sed -i 's/$amdgpudistro/8.5/g' /etc/yum.repos.d/amdgpu*.repo
    if  [ "$(dnf list installed | grep mesa-libOpenCL | wc -l)" == 1 ]; then
        echo "Removing Mesa OpenCL"
        dnf remove mesa-libOpenCL -y
    fi
    buildWorkaround
    dnf install ocl-icd rocm-opencl-runtime libdrm-amdgpu -y
    
}

installLegacyOpenCL()
{
	if [ "$(ls $(pwd) | grep *amdgpu-pro-21.30*.tar.xz | wc -l)" == 1 ] 
	then
		buildWorkaround
		tar -xvf $(pwd)/*amdgpu-pro-21.30*.xz
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
		dnf install opencl-rocr-amdgpu-pro -y
		echo "Installation Successful"
	else
		echo "Please Download https://drivers.amd.com/drivers/linux/amdgpu-pro-21.30-1290604-rhel-8.4.tar.xz from this link https://www.amd.com/en/support/kb/release-notes/rn-amdgpu-unified-linux-21-30 and place it in the Parent Directory of this Script"
		exit
	fi
}

yesno()
{
	echo "A local repo will setup"
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
    dnf remove rocm-opencl-runtime libdrm-amdgpu amdgpu-core-shim opencl-rocr-amdgpu-pro -y
    dnf remove amdgpu-install -y
    rm -rf /var/local/amdgpu
    rm -rf /etc/yum.repo.d/amdgpu*
    rm -rf /etc/yum.repo.d/rocm
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
