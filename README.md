# WakeUp

Alarm clock for Ubuntu Touch with **slowly rising volume**.

- Alarms are normal system alarms: they wake the phone, show Snooze/OK and also appear in the Clock app.
- Repeat on chosen weekdays, a description, any system ringtone.
- **Slowly rising volume:** the alarm starts quiet and reaches full volume after 30 s, 1, 2 or 5 minutes.
- System alarm settings in one place: snooze length, ring time, volume, vibration.
- English, Danish, German, French, Spanish, Italian and Dutch.

## How rising volume works
The system plays an alarm sound at one fixed volume and starts it again when it ends. So WakeUp makes a
copy of the ringtone that is as long as the ring time and has the fade-in built in
(`~/.local/share/wakeup.henrik68/rising/`, about 4 MB per 10 minutes). This takes about 20 seconds when
you save an alarm. If you make the ring time longer, WakeUp makes the copies longer the next time it is open.

## Known limits
- Snooze can't be switched off per alarm (the system always shows a Snooze button).
- If you delete or switch off an alarm while it is snoozed, the snooze still rings once more. This is a bug in
  the system alarm service (ayatana-indicator-datetime, also seen with the Clock app); a confined app can't work
  around it. Tip: tap OK instead of Snooze when you want to stop an alarm for good.

## Build
`bash build-click.sh` (needs [clickable](https://clickable-ut.dev) and podman or docker).
Translations: `po/*.po`, update with `update-translations.sh`.

License: GNU GPL v3 (see LICENSE).
