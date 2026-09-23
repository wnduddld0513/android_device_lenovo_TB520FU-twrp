#!/system/bin/sh
# Start gatekeeper only after keymint has finished its TZ initialisation.
# Started concurrently, gatekeeper's first TZ call blocks on an smcinvoke
# callback and keymint only ever gets BUSY (IAppClient_getAppObject -99).
# Metadata decryption needs keymint only; gatekeeper is needed later for the
# lock screen credential.

# wait until keymint-qti has stayed up for a few seconds (it aborts within
# ~5 s when its TZ init fails)
stable=0
for i in $(seq 1 60); do
    if [ "$(getprop init.svc.vendor.keymint-qti)" = "running" ]; then
        stable=$((stable + 1))
    else
        stable=0
    fi
    [ $stable -ge 6 ] && break
    sleep 1
done
log -t start_gatekeeper "keymint stable=$stable after ${i}s, starting gatekeeper"
setprop vendor.twrp.gatekeeper.start 1
