#!/usr/bin/env sh
set -e

rootCheck()
{
    if [[ $UID -ne 0 ]]; then
        sudo -p 'Restarting as Root, Password: ' bash $0 "$@"
        exit $?
    fi
}

installOpenCL()
{
    dnf install http://repo.radeon.com/amdgpu-install/latest/rhel/8.5/amdgpu-install-21.40.40500-1.noarch.rpm -y
    sed -i 's/$amdgpudistro/8.5/g' /etc/yum.repos.d/amdgpu*.repo
    if  [ "$(dnf list installed | grep mesa-libOpenCL | wc -l)" == 1 ]; then
        echo "Removing Mesa OpenCL"
        dnf remove mesa-libOpenCL -y
    fi
    if  [ "$(dnf list installed | grep rpm-build.$(arch) | wc -l)" == 0 ]; then
        dnf install rpm-build -y
        remove=1
        echo remove
    fi
    rpmbuild -bb ./amdgpu-core-shim.spec --define "_rpmdir $(pwd)"
    dnf install $(pwd)/$(arch)/amdgpu-core-shim*.rpm -y
    dnf install rocm-opencl-runtime libdrm-amdgpu -y
    if  [ "$remove" == 1 ]; then
        dnf remove rpm-build -y
    fi
}

uninstallOpenCL()
{
    dnf remove rocm-opencl-runtime libdrm-amdgpu amdgpu-core-shim -y
    dnf remove amdgpu-install -y
}

menu()
{
    PS3='Enter Option Number: '
    options=("Install" "Uninstall" "Quit")
    select opt in "${options[@]}"
    do
        case $opt in
            "Install")
                echo "Installing OpenCL Stack"
                installOpenCL
                echo "Install Successful"
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
            *) echo "invalid option $REPLY";;
        esac
    done

}

#Driver Code
rootCheck
menu
