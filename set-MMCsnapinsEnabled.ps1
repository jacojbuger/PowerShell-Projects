#Microsoft’s guidance and community documentation confirm that you can enable MMC and other GUI-based tools by installing the ServerCore.AppCompatibility capability.
#This adds support for MMC, Device Manager, Disk Management, Event Viewer, and many common .msc snap-ins.

Add-WindowsCapability -Online -Name ServerCore.AppCompatibility~~~~0.0.1.0 
