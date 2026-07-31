# Fire a test notification

Click **Test Notification** (or run *Claude Chime: Test Notification* from
the Command Palette).

It writes a real signal file for this window's workspace folder — exercising
the same watcher → window-matching → toast pipeline that live Claude Code
events use. Within a second you should see:

> Claude finished responding — *your-folder*: "Test notification — Claude
> Chime is working"

No toast? Check that a folder is open in this window, then see the
[troubleshooting guide](https://github.com/rvira/claude-plugins/blob/main/TROUBLESHOOTING.md).
