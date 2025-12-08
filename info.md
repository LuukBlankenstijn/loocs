# General information about the XZ Utils attack

## Timeline
- https://research.swtch.com/xz-timeline

## Reproduction
- Repo with reproduction code of XZ: <https://github.com/0xlane/xz-cve-2024-3094>
- Tutorial on how to reproduce the attack: <https://hackmd.io/@cve-2024-3094/how-to-extract-the-malware-payload>
- XZ explanation (mentioned in above tutorial): <https://research.swtch.com/xz-script> 
- Exploit demo: <https://github.com/amlweems/xzbot>

## Step-by-step
- https://arstechnica.com/security/2024/04/what-we-know-about-the-xz-utils-backdoor-that-almost-infected-the-world/
- https://gynvael.coldwind.pl/?lang=en&id=782

## Background information
- glibc's IFUNC mechanism (allows dynamically linking of functions): <https://sourceware.org/glibc/wiki/GNU_IFUNC>
- m4 (a general purpose macro processor): <https://www.gnu.org/software/m4/manual/m4.html>

## Short overview
### Timeline
- Social engineering resulting in Jia Tan getting maintainer access to XZ Utils
- In multiple steps, Jia Tan introduced a backdoor into the XZ Utils codebase
  - Binary test files were added, containing obfuscated bash scripts and compiled object files
  - Version 5.6.0 is published by Jia Tan, containing the backdoor
  - An additional m4 script (sort of build script) is added, which adds the backdoor when the deb/rpm packages are built
  - Multiple changes are made, and version 5.6.1 is published, which contains an updated backdoor
- The backdoor is in Debian unstable, and Jia Tan attempts to also get it into Ubuntu
- The backdoor is discovered by Andres Freund

### Workings:
- Binary test files contain obfuscated bash scripts
- An m4 script is added, which adds the backdoor when the deb/rpm packages are built for x86-64 Linux
  - When the script is built, the bash script is extracted from one of the binary test files
  - This bash script is executed, which extracts a pre-compiled object file from another binary test file
  - This generated bash script injects the pre-compiled object file into the XZ Utils compiled code
  - The code, including the backdoor, is then compiled into the final binaries, which get distributed
- Then, when the exploited version of XZ Utils is installed on a system, the backdoor runs when certain conditions are met
  - These conditions include: arch: x86_64, os: Linux, glibc available, built via rpm/deb, sshd must load xz
  - The backdoor does not run when certain environment variables are set, to avoid detection when debugging
  - The backdoor replaces the normal version of RSA_public_decrypt from OpenSSL with a malicious version, using glibc's IFUNC mechanism
    - The backdoor is then triggered when a specific key is used, in which case access is granted. For this, a hardcoded public key is stored in the backdoor code
