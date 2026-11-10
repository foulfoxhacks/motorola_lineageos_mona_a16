<#
.SYNOPSIS
    Read-only SIM / modem / registration dump for mona on the GSI.

.DESCRIPTION
    "No service" has three very different causes and they need different fixes:

      1. the card is not being read at all   (gsm.sim.state = ABSENT / NOT_READY)
      2. the card is read but the UICC app is disabled (the "Use SIM" toggle)
      3. the card is fine and the phone will not register (network / APN / IMS)

    This prints the few values that separate them, plus the radio log tail.

    Nothing is written. ICCID and EID values are masked, but the -Log tail can still
    contain IMSI/ICCID/phone numbers: review it before pasting it anywhere public.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\radio-check.ps1

.EXAMPLE
    # include the last 300 radio log lines
    powershell -ExecutionPolicy Bypass -File .\scripts\radio-check.ps1 -Log
#>

param(
    [switch]$Log,
    [int]$LogLines = 300
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_common.ps1')

function Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Info($m) { if ("$m".Trim()) { Write-Host "  $m" } }
function Val($k, $v) { Write-Host ("  {0,-28} {1}" -f $k, ("$v".Trim())) }

Ensure-PlatformTools
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) { Write-Host 'adb not found' -ForegroundColor Red; exit 1 }

function Sh([string]$Cmd) {
    # Flatten stderr so PS 5.1 does not decorate the output with "At <script>".
    $o = (& adb shell $Cmd 2>&1) | ForEach-Object { "$_" } | Out-String
    return $o.Trim()
}
function Prop([string]$Name) { return (Sh "getprop $Name").Trim() }
function Mask([string]$v) {
    # Keep presence + last 4 digits only; identifiers must not end up in public issue threads.
    $v = "$v".Trim()
    if ($v.Length -le 4) { return $v }
    return ('*' * ($v.Length - 4)) + $v.Substring($v.Length - 4)
}

$state = (& adb get-state 2>$null) | Select-Object -First 1
if ("$state".Trim() -ne 'device') {
    Write-Host @'
no adb device.

  adb devices        # must print: <serial>  device

If the phone is in the bootloader, run: fastboot reboot
'@ -ForegroundColor Red
    exit 1
}

$isRoot = ((Sh 'id') -match 'uid=0')

Step 'Device'
Val 'lineage'      (Prop ro.lineage.version)
Val 'android'      (Prop ro.build.version.release)
Val 'device'       (Prop ro.product.device)
Val 'slot'         (Prop ro.boot.slot_suffix)
$rootText = if ($isRoot) { 'yes' } else { 'no (adb root / Magisk)' }
Val 'root'         $rootText

Step 'SIM presence  (is the card read at all?)'
Val 'gsm.sim.state'          (Prop gsm.sim.state)
Val 'ril.iccid.sim1'         (Mask (Prop ril.iccid.sim1))
Val 'gsm.sim.operator.alpha' (Prop gsm.sim.operator.alpha)
Val 'gsm.sim.operator.numeric' (Prop gsm.sim.operator.numeric)
Val 'gsm.sim.operator.iso-country' (Prop gsm.sim.operator.iso-country)

Step 'eSIM / eUICC  (this device has no usable tray - the line is an eSIM)'
Val 'ro.euicc.supported'        (Prop ro.euicc.supported)
Val 'ro.vendor.product.name'    (Prop ro.vendor.product.name)
Info '--- LPA / euicc packages ---'
Info (Sh "pm list packages 2>/dev/null | grep -iE 'euicc|lpa|esim|simapp|simtoolkit'")
Info '--- dumpsys euicc (profile state) ---'
Info (Sh "dumpsys euicc 2>/dev/null | grep -iE 'profile|state|active|slot|eid|switch' | sed -E 's/[0-9A-Fa-f]{12,}/<redacted>/g' | cut -c1-180 | head -25")
Info '--- sim slot mapping ---'
Info (Sh "cmd phone get-sim-card-mapping 2>&1 | head -10")

Step 'Registration'
Val 'gsm.operator.alpha'   (Prop gsm.operator.alpha)
Val 'gsm.operator.numeric' (Prop gsm.operator.numeric)
Val 'gsm.network.type'     (Prop gsm.network.type)
Val 'gsm.data.network.type' (Prop gsm.data.network.type)
Val 'gsm.operator.isroaming' (Prop gsm.operator.isroaming)
Val 'gsm.sim.state (again)' (Prop gsm.sim.state)

Step 'NR / 5G'
Val 'ro.telephony.default_network'  (Prop ro.telephony.default_network)
Val 'preferred_network_mode'        (Sh 'settings get global preferred_network_mode')
Val 'preferred_network_mode1'       (Sh 'settings get global preferred_network_mode1')
Info '--- NR attach evidence (the modem, not the GSI, owns this) ---'
Info (Sh "dumpsys telephony.registry | grep -m2 'mServiceState=' | grep -oE 'accessNetworkTechnology=[A-Z]+|isNrAvailable=[a-z]+|mVopsSupport=[0-9]+|mBands=\[[^]]*\]|mNrFrequencyRange=[0-9]+' | tr '\n' ' '")
Info '--- telephony overlays (a forced-LTE overlay blocks NR) ---'
Info (Sh "cmd overlay list 2>/dev/null | grep -i telephony")

Step 'Airplane mode / radio power'
Val 'airplane_mode_on'          (Sh 'settings get global airplane_mode_on')
Val 'persist.radio.airplane_mode_on' (Prop persist.radio.airplane_mode_on)
Val 'ro.radio.noril'            (Prop ro.radio.noril)
Val 'ro.telephony.default_network' (Prop ro.telephony.default_network)

Step 'Service state'
$ss = Sh "dumpsys telephony.registry | grep -m1 'mServiceState=' | grep -oE 'mVoiceRegState=[^,]+|mDataRegState=[^,]+|mOperatorAlphaLong=[^,]*|getRilVoiceRadioTechnology=[^,]+|getRilDataRadioTechnology=[^,]+|mIsEmergencyOnly=[a-z]+' | tr '\n' ' '"
Info $ss
$reg = Sh "dumpsys telephony.registry | grep -m1 'mSignalStrength=' | grep -oE 'mLte=[^,]*|mNr=[^,]*' | cut -c1-120 | tr '\n' ' '"
Info $reg

Step 'Subscriptions (isub)'
$sub = Sh "dumpsys isub 2>/dev/null | grep -oE 'simSlotIndex=-?[0-9]+|areUiccApplicationsEnabled=[01]|displayName=[^ ]+|carrierName=[^ ]+|type=[A-Z_]+' | head -20"
if ($sub) { Info $sub } else { Info '(no dumpsys isub output)' }
Info '--- uicc slots ---'
Info (Sh "dumpsys isub 2>/dev/null | grep -iE 'uiccslot|mUiccSlots|isActive|cardState' | cut -c1-200 | head -10")
Info '--- cmd phone (runs inside the phone process; any uicc switch would work without root) ---'
Info (Sh "cmd phone help 2>&1 | grep -iE 'uicc|application|sim|subscription|esim' | head -20")

Step 'Telephony provider / siminfo'
if ($isRoot) {
    Info (Sh "su -c 'content query --uri content://telephony/siminfo --projection _id,sim_slot_index,uicc_applications_enabled,display_name,carrier_name 2>&1'")
} else {
    Info '(needs root - run: adb root, or use the Magisk su)'
}

Step 'IMS / RIL props'
Info (Sh "getprop | grep -iE 'phh.ims|phh.ril|volte|wfc|vt_|qcril'")

Step 'Preferred network mode'
Val 'preferred_network_mode'  (Sh 'settings get global preferred_network_mode')
Val 'preferred_network_mode1' (Sh 'settings get global preferred_network_mode1')

Step 'FRP block'
Val 'ro.frp.pst' (Prop ro.frp.pst)
if ($isRoot) {
    Info (Sh "su -c 'ls -l /dev/block/by-name/ | grep -iE \"frp|persist\"'")
}

if ($Log) {
    Step "Radio log (last $LogLines lines)"
    Info (Sh "logcat -b radio -d -t $LogLines 2>/dev/null | grep -iE 'SIM_STATE|UiccCard|CARD_STATE|APP_FAMILY|icc|NOT_READY|REGISTRATION|reject|CS|PS' | tail -60")
}

Write-Host @'

==================================================================
How to read it

  simSlotIndex=-1  (+ areUiccApplicationsEnabled=0)
      the DB row exists but is bound to no slot, so the framework never
      talks to the modem about it. The modem reports the card as ABSENT.
      -> this is the "Use SIM toggle broke it" state.
      -> a reboot does NOT fix it, and `content update` does NOT either:
         that only edits the DB, it never sends SET_UICC_APPLICATIONS_ENABLE
         to the modem.

  eSIM (no tray on this unit - the line is an embedded profile)
      slot 0 ABSENT + slot 1 NOT_READY is NORMAL for an eSIM-only setup:
      slot 0 is the empty physical slot, slot 1 is the eUICC.
      -> the profile has to be re-enabled through the LPA / EuiccManager,
         not by re-seating anything.
      -> Settings -> Network & internet -> SIMs -> T-Mobile -> Use SIM
      -> or the eSIM manager: Settings -> SIMs -> "Add SIM" / download
      -> if dumpsys euicc shows the profile as inactive, no reboot and no
         GSI flash will turn it back on - the eUICC itself has it disabled.

  gsm.sim.state = ABSENT / NOT_READY
      the modem is not reading the card.
      -> physical SIM: power off, re-seat the tray, boot.
      -> eSIM: see the eSIM block above.

  gsm.sim.state = LOADED but gsm.operator.numeric is empty
      card is fine, the UICC application is disabled.
      -> Settings -> SIMs -> Use SIM  off then on  (this is the call that
         actually reaches the modem)
      -> or: pm clear com.android.providers.telephony + reboot

  gsm.operator.numeric = 310260 (T-Mobile) but no voice
      registered on LTE with no voice domain -> IMS/VoLTE, not the SIM.
      -> Treble Settings -> IMS -> CAF IMS -> reboot
         (setprop alone gets reset by the phh boot scripts)

  gsm.operator.numeric = 310410 (AT&T) while the line is Metro
      the modem attached to the wrong network / emergency only.
      -> Treble Settings -> IMS -> CAF IMS -> reboot
      -> settings put global preferred_network_mode 33
==================================================================
'@ -ForegroundColor Green
