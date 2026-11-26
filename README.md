# nv-audit
A shell script to help determine which linux applications are trying to fall back on nouveau drivers.

I set up this script to help isolate faulty applications due to graphic driver issues. I began experiencing problems on my Debian machine after switching over to the most recent nvidia drivers and completely excising fallbacks. 

This script cuts down the time required to find configuration files and help troubleshoot graphics related problems on linux systems. 
