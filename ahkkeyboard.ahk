; AutoHotkey v1.1 - Gradual acceleration (your original AccelLoop)
; + Arm/Disarm (F9), blocking behavior while ARMED, auto-switch-after-timer
#NoEnv
SendMode Input
SetWorkingDir %A_ScriptDir%
SetBatchLines -1
#MaxThreadsPerHotkey 1

; ====== CONFIG ======
movementKeys := ["w","a","s","d"]
initialDelay := 150    ; ms between sends at start
minDelay := 20         ; fastest (ms) when fully accelerated
accelStep := 5         ; ms reduced from delay after each send
baseTick := 20         ; timer resolution (ms)
gradualTime := 5000    ; ms before switching to normal hold (5s)
toggleKey := "F9"      ; key to arm/disarm gradual mode
; ====================

; runtime state
held := {}       ; held[key] = true/false (script-controlled pulsing)
delayMap := {}   ; delayMap[key] = current delay in ms
lastSent := {}   ; lastSent[key] = A_TickCount when last sent
startTime := {}  ; when gradual started for this key
timerActive := false
armed := true    ; start ARMED (ready to intercept first press)

; initialize state for keys
for index, k in movementKeys {
    held[k] := false
    delayMap[k] := initialDelay
    lastSent[k] := 0
    startTime[k] := 0
}

; --- Register hotkeys dynamically (works with variable names) ---
Hotkey, % "$" toggleKey, ToggleMode, On

for index, k in movementKeys {
    Hotkey, % "$*" k, HandleKey, On
    Hotkey, % "$*" k " Up", HandleKeyUp, On
}

; If starting DISARMED, turn movement hotkeys off so keypresses are native
if (!armed) {
    for index, k in movementKeys {
        Hotkey, % "$*" k, Off
        Hotkey, % "$*" k " Up", Off
    }
}

; -------- Toggle Mode (F9) ----------
ToggleMode:
{
    armed := !armed
    if (armed) {
        ; enable blocking hotkeys (script will intercept keys)
        for index, k in movementKeys {
            Hotkey, % "$*" k, HandleKey, On
            Hotkey, % "$*" k " Up", HandleKeyUp, On
        }
        TrayTip, Gradual Throttle, Mode: ARMED, 1000, 1
    } else {
        ; disable blocking hotkeys -> keys are native
        for index, k in movementKeys {
            Hotkey, % "$*" k, Off
            Hotkey, % "$*" k " Up", Off
        }
        TrayTip, Gradual Throttle, Mode: DISARMED, 1000, 1
    }
    Return
}

; -------- HandleKey (down) - generic for all movement keys ----------
HandleKey:
{
    ; Extract key name from A_ThisHotkey, e.g. "$*w" -> "w"
    key := RegExReplace(A_ThisHotkey, "^\$\*|\s+Up$", "")

    ; If not armed, just send native down/hold and wait for release
    if (!armed) {
        SendInput, % "{" key " down}"
        KeyWait, %key%    ; wait until release
        SendInput, % "{" key " up}"
        Return
    }

    ; ARMED: start pulsing for this key (if not already)
    if (!held[key]) {
        held[key] := true
        delayMap[key] := initialDelay
        lastSent[key] := 0
        startTime[key] := A_TickCount
        if (!timerActive) {
            SetTimer, AccelLoop, % baseTick
            timerActive := true
        }
    }
    Return
}

; -------- HandleKeyUp (key release) ----------
HandleKeyUp:
{
    key := RegExReplace(A_ThisHotkey, "^\$\*|\s+Up$", "")

    ; If not armed the hotkey was Off and native up already happened (no-op)
    if (!armed) {
        Return
    }

    ; Stop pulsing for this key
    held[key] := false
    lastSent[key] := 0
    startTime[key] := 0
    Return
}

; -------- AccelLoop (your original acceleration engine) ----------
AccelLoop:
{
    global held, delayMap, lastSent, accelStep, minDelay, baseTick, movementKeys, timerActive, startTime, gradualTime, armed

    now := A_TickCount
    anyHeld := false

    for index, key in movementKeys {
        if (held[key]) {
            anyHeld := true

            ; if held long enough, switch to normal hold and disarm
            if (now - startTime[key] >= gradualTime) {
                ; Send virtual down to hold the key
                SendInput, % "{" key " down}"
                ; stop pulsing
                held[key] := false

                ; Disarm so future presses are native
                armed := false

                ; Disable all movement hotkeys so the physical key's release is native
                for i, kk in movementKeys {
                    Hotkey, % "$*" kk, Off
                    Hotkey, % "$*" kk " Up", Off
                }

                TrayTip, Gradual Throttle, Auto-switched to normal hold & DISARMED, 1200, 1

                ; Wait for physical release of this key, then release our virtual hold
                while (GetKeyState(key, "P")) {
                    Sleep, 30
                }
                SendInput, % "{" key " up}"

                ; After handling this key's transition, continue to next keys
                continue
            }

            ; first-send immediately if not sent yet
            if (lastSent[key] = 0) {
                SendInput, %key%
                lastSent[key] := now
                delayMap[key] -= accelStep
                if (delayMap[key] < minDelay)
                    delayMap[key] := minDelay
                continue
            }

            ; subsequent sends based on each key's delay
            interval := delayMap[key]
            if (now - lastSent[key] >= interval) {
                SendInput, %key%
                lastSent[key] := now

                ; accelerate: reduce delay
                delayMap[key] -= accelStep
                if (delayMap[key] < minDelay)
                    delayMap[key] := minDelay
            }
        }
    }

    ; stop the timer if nothing is being held
    if (!anyHeld) {
        SetTimer, AccelLoop, Off
        timerActive := false
    }
}
Return

