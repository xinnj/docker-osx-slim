FROM archlinux:base
LABEL maintainer='xinnj@hotmail.com'

SHELL ["/bin/bash", "-c"]

# OPTIONAL: Arch Linux server mirrors for super fast builds
ARG MIRROR_COUNTRY=US

RUN curl -L -o /etc/pacman.d/mirrorlist "https://www.archlinux.org/mirrorlist/?country=${MIRROR_COUNTRY:-US}&protocol=https&use_mirror_status=on" \
    && sed -i -e 's/^#Server/Server/' -e '/^#/d' /etc/pacman.d/mirrorlist \
    && cat /etc/pacman.d/mirrorlist \
    && useradd arch -p arch \
    && usermod -a -G kvm arch \
    && tee -a /etc/sudoers <<< 'arch ALL=(ALL) NOPASSWD: ALL' \
    && mkdir -p /home/arch \
    && chown arch:arch /home/arch

RUN yes | pacman -Sy linux qemu-desktop sudo openssh xorg-server-xvfb xorg-xrandr sshpass guestfs-tools --noconfirm \
    && yes | pacman -Scc

RUN libguestfs-test-tool || exit 1 \
    ; rm -rf /var/tmp/.guestfs-*

USER arch
WORKDIR /home/arch/OSX-KVM

ADD --chown=arch:arch --chmod=755 OSX-KVM/macserial /home/arch/OSX-KVM/
ADD --chown=arch:arch OSX-KVM/vendor_macs.tsv /home/arch/OSX-KVM/
ADD --chown=arch:arch OSX-KVM/default-env /home/arch/OSX-KVM/

COPY --from=sickcodes/docker-osx:naked /home/arch/OSX-KVM/OVMF_CODE.fd /home/arch/OSX-KVM/
COPY --from=sickcodes/docker-osx:naked /home/arch/OSX-KVM/OVMF_VARS-1024x768.fd /home/arch/OSX-KVM/
COPY --from=sickcodes/docker-osx:naked /home/arch/OSX-KVM/OpenCore/OpenCore-nopicker.qcow2 /home/arch/OSX-KVM/OpenCore/
COPY --from=sickcodes/docker-osx:naked /home/arch/OSX-KVM/Docker-OSX/osx-serial-generator/generate-unique-machine-values.sh /home/arch/OSX-KVM/Docker-OSX/osx-serial-generator/
COPY --from=sickcodes/docker-osx:naked /home/arch//OSX-KVM/OpenCore/EFI /home/arch/OSX-KVM/OpenCore/EFI/
COPY --from=sickcodes/docker-osx:naked /home/arch//OSX-KVM/resources/OcBinaryData/Resources /home/arch/OSX-KVM/resources/OcBinaryData/Resources/
COPY --from=sickcodes/docker-osx:naked /home/arch//OSX-KVM/opencore-image-ng.sh /home/arch//OSX-KVM/
COPY --from=sickcodes/docker-osx:naked /home/arch/OSX-KVM/config-custom.plist /home/arch/OSX-KVM/

RUN touch Launch.sh \
    && chmod +x ./Launch.sh \
    && tee -a Launch.sh <<< '#!/bin/bash' \
    && tee -a Launch.sh <<< 'set -eu' \
    && tee -a Launch.sh <<< 'sudo touch /dev/kvm /dev/snd "${IMAGE_PATH}" "${BOOTDISK}" "${ENV}" 2>/dev/null || true' \
    && tee -a Launch.sh <<< 'sudo chown -R $(id -u):$(id -g) /dev/kvm /dev/snd "${IMAGE_PATH}" "${BOOTDISK}" "${ENV}" 2>/dev/null || true' \
    && tee -a Launch.sh <<< 'sudo chmod -R 777 /tmp/.X11-unix 2>/dev/null || true' \
    && tee -a Launch.sh <<< '[[ "${RAM}" = max ]] && export RAM="$(("$(head -n1 /proc/meminfo | tr -dc "[:digit:]") / 1000000"))"' \
    && tee -a Launch.sh <<< '[[ "${RAM}" = half ]] && export RAM="$(("$(head -n1 /proc/meminfo | tr -dc "[:digit:]") / 2000000"))"' \
    && tee -a Launch.sh <<< 'export HOST_SHARE_PARAMS=""' \
    && tee -a Launch.sh <<< 'if [[ ! -z "${HOST_SHARE}" ]]; then' \
    && tee -a Launch.sh <<< '  export HOST_SHARE_PARAMS="-virtfs local,path=${HOST_SHARE},mount_tag=hostshare,security_model=passthrough,id=hostshare"' \
    && tee -a Launch.sh <<< 'fi' \
    && tee -a Launch.sh <<< 'exec qemu-system-x86_64 -m ${RAM}G \' \
    && tee -a Launch.sh <<< '-cpu ${CPU},${CPUID_FLAGS}${BOOT_ARGS} \' \
    && tee -a Launch.sh <<< '-machine q35,${KVM} \' \
    && tee -a Launch.sh <<< '-smp ${CPU_STRING:-${SMP},cores=${CORES}} \' \
    && tee -a Launch.sh <<< '-usb -device usb-kbd -device usb-tablet \' \
    && tee -a Launch.sh <<< '-device isa-applesmc,osk=ourhardworkbythesewordsguardedpleasedontsteal\(c\)AppleComputerInc \' \
    && tee -a Launch.sh <<< '-drive if=pflash,format=raw,readonly=on,file=/home/arch/OSX-KVM/OVMF_CODE.fd \' \
    && tee -a Launch.sh <<< '-drive if=pflash,format=raw,file=/home/arch/OSX-KVM/OVMF_VARS-1024x768.fd \' \
    && tee -a Launch.sh <<< '-smbios type=2 \' \
    && tee -a Launch.sh <<< '-audiodev ${AUDIO_DRIVER:-alsa},id=hda -device ich9-intel-hda -device hda-duplex,audiodev=hda \' \
    && tee -a Launch.sh <<< '-device ich9-ahci,id=sata \' \
    && tee -a Launch.sh <<< '-drive id=OpenCoreBoot,if=none,snapshot=on,format=qcow2,file=${BOOTDISK} \' \
    && tee -a Launch.sh <<< '-device ide-hd,bus=sata.2,drive=OpenCoreBoot \' \
    && tee -a Launch.sh <<< '-drive id=MacHDD,if=none,file=${IMAGE_PATH},format=${IMAGE_FORMAT} \' \
    && tee -a Launch.sh <<< '-device ide-hd,bus=sata.4,drive=MacHDD \' \
    && tee -a Launch.sh <<< '-netdev user,id=net0,dnssearch=default.svc.cluster.local,dnssearch=svc.cluster.local,hostfwd=tcp::${INTERNAL_SSH_PORT}-:22,hostfwd=tcp::${SCREEN_SHARE_PORT}-:5900,${ADDITIONAL_PORTS} \' \
    && tee -a Launch.sh <<< '-device ${NETWORKING},netdev=net0,id=net0,mac=${MAC_ADDRESS} \' \
    && tee -a Launch.sh <<< '-monitor stdio \' \
    && tee -a Launch.sh <<< '-boot menu=on \' \
    && tee -a Launch.sh <<< '-vga vmware \' \
    && tee -a Launch.sh <<< '${HOST_SHARE_PARAMS} \' \
    && tee -a Launch.sh <<< '-rtc base=localtime \' \
    && tee -a Launch.sh <<< '${EXTRA:-}'

RUN mkdir -p ~/.ssh \
    && touch ~/.ssh/authorized_keys \
    && touch ~/.ssh/config \
    && chmod 700 ~/.ssh \
    && chmod 600 ~/.ssh/config \
    && chmod 600 ~/.ssh/authorized_keys \
    && tee -a ~/.ssh/config <<< 'Host *' \
    && tee -a ~/.ssh/config <<< '    StrictHostKeyChecking no' \
    && tee -a ~/.ssh/config <<< '    UserKnownHostsFile=/dev/null'

RUN touch Auto.sh \
    && chmod +x ./Auto.sh \
    && tee -a Auto.sh <<< '#!/bin/bash' \
    && tee -a Auto.sh <<< 'export DISPLAY=:99' \
    && tee -a Auto.sh <<< 'Xvfb ${DISPLAY} -screen 0 1920x1080x16 &' \
    && tee -a Auto.sh <<< 'until [[ "$(xrandr --query 2>/dev/null)" ]]; do sleep 1 ; done' \
    && tee -a Auto.sh <<< '[[ -s "${SSH_KEY}" ]] || {' \
    && tee -a Auto.sh <<< '  /usr/bin/ssh-keygen -t rsa -f "${SSH_KEY}" -q -N ""' \
    && tee -a Auto.sh <<< '  chmod 600 "${SSH_KEY}"' \
    && tee -a Auto.sh <<< '}' \
    && tee -a Auto.sh <<< '/bin/bash -c ./Launch.sh & echo "Booting Docker-OSX in the background. Please wait..."' \
    && tee -a Auto.sh <<< 'for i in {1..20}; do' \
    && tee -a Auto.sh <<< '  sshpass -p${PASSWORD:=Jenkins} ssh-copy-id -f -i "${SSH_KEY}.pub" -p 10022 ${USERNAME:=jenkins}@127.0.0.1 > /dev/null' \
    && tee -a Auto.sh <<< '  if [[ "$?" == "0" ]]; then' \
    && tee -a Auto.sh <<< '    break' \
    && tee -a Auto.sh <<< '  else' \
    && tee -a Auto.sh <<< '    echo "Repeating until able to copy SSH key into OSX..."' \
    && tee -a Auto.sh <<< '    if [[ "$i" == "20" ]]; then' \
    && tee -a Auto.sh <<< '      echo "Connect macos vm failed!"' \
    && tee -a Auto.sh <<< '      while killall -15 qemu-system-x86_64; do' \
    && tee -a Auto.sh <<< '        echo "Shutting down macos..."' \
    && tee -a Auto.sh <<< '        sleep 1' \
    && tee -a Auto.sh <<< '      done' \
    && tee -a Auto.sh <<< '      echo "Shutdown macos finished, exit."' \
    && tee -a Auto.sh <<< '      exit 1' \
    && tee -a Auto.sh <<< '    fi' \
    && tee -a Auto.sh <<< '    sleep 5' \
    && tee -a Auto.sh <<< '  fi' \
    && tee -a Auto.sh <<< 'done' \
    && tee -a Auto.sh <<< 'grep ${SSH_KEY} ~/.ssh/config || {' \
    && tee -a Auto.sh <<< '  tee -a ~/.ssh/config <<< "Host 127.0.0.1"' \
    && tee -a Auto.sh <<< '  tee -a ~/.ssh/config <<< "    User ${USERNAME:=jenkins}"' \
    && tee -a Auto.sh <<< '  tee -a ~/.ssh/config <<< "    Port 10022"' \
    && tee -a Auto.sh <<< '  tee -a ~/.ssh/config <<< "    IdentityFile ${SSH_KEY}"' \
    && tee -a Auto.sh <<< '  tee -a ~/.ssh/config <<< "    StrictHostKeyChecking no"' \
    && tee -a Auto.sh <<< '  tee -a ~/.ssh/config <<< "    UserKnownHostsFile=~/.ssh/known_hosts"' \
    && tee -a Auto.sh <<< '}' \
    && tee -a Auto.sh <<< 'echo "Execute on macos: ${OSX_COMMANDS}"' \
    && tee -a Auto.sh <<< 'ssh 127.0.0.1 "${OSX_COMMANDS}"'

RUN touch Start.sh \
    && chmod +x ./Start.sh \
    && tee -a Start.sh <<< '#!/bin/bash' \
    && tee -a Start.sh <<< '[[ -s "${ENV}" ]] && [[ -s "${BOOTDISK}" ]] && [[ "${GENERATE_UNIQUE}" == false ]] || {' \
    && tee -a Start.sh <<< '  echo "Generate unique machine value."' \
    && tee -a Start.sh <<< '  ./Docker-OSX/osx-serial-generator/generate-unique-machine-values.sh \' \
    && tee -a Start.sh <<< '    --master-plist="./config-custom.plist" \' \
    && tee -a Start.sh <<< '    --count 1 \' \
    && tee -a Start.sh <<< '    --bootdisks \' \
    && tee -a Start.sh <<< '    --output-bootdisk "${BOOTDISK}" \' \
    && tee -a Start.sh <<< '    --output-env "${ENV}"' \
    && tee -a Start.sh <<< '}' \
    && tee -a Start.sh <<< '[[ -s "${ENV}" ]] && {' \
    && tee -a Start.sh <<< '  source "${ENV}"' \
    && tee -a Start.sh <<< '}' \
    && tee -a Start.sh <<< 'if [[ "${HEADLESS}" = true ]]; then' \
    && tee -a Start.sh <<< '  /bin/bash -c ./Auto.sh' \
    && tee -a Start.sh <<< 'else' \
    && tee -a Start.sh <<< '  /bin/bash -c ./Launch.sh' \
    && tee -a Start.sh <<< 'fi'

ENV RAM=4
ENV CPU=Penryn
ENV CPUID_FLAGS='vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,check,'
ENV SMP=4
ENV CORES=4
ENV BOOT_ARGS=
ENV KVM='accel=kvm:tcg'
ENV HEADLESS=false
ENV IMAGE_PATH=/image
ENV BOOTDISK=/home/arch/OSX-KVM/OpenCore/OpenCore-nopicker.qcow2
ENV BASESYSTEM_FORMAT=qcow2
ENV ENV=/home/arch/OSX-KVM/default-env
ENV IMAGE_FORMAT=qcow2
ENV INTERNAL_SSH_PORT=10022
ENV SCREEN_SHARE_PORT=5900
ENV ADDITIONAL_PORTS=
ENV NETWORKING=vmxnet3
ENV SSH_KEY=/home/arch/.ssh/id_docker_osx
ENV HOST_SHARE=
ENV OSX_COMMANDS=
ENV GENERATE_UNIQUE=false

CMD ./Start.sh
