# Bash-Script-Automatic-Static-Route-Management

**Overview:**

This Bash script automates the management of static routes on multiple Linux machines. It simplifies tasks like adding, deleting, and printing static route configurations, saving time and effort compared to manual configuration. Designed for Linux system administrators, it offers convenience and automation.

**Features:**

    Supports:
        Adding, deleting, and printing static routes.
        Different functionalities based on user action (add, delete, or print).
        Multiple Linux distributions with automatic command adjustments.
    Benefits:
        Saves time and effort compared to manual configuration.
        Reduces errors with streamlined automation.
        Improves efficiency and consistency across multiple machines.

**Usage:**

    Download: Get the script from [insert GitHub repository link].

    Make executable: chmod +x add_static_routes.sh

    Run: Use the following command, replacing placeholders with your files:
    Bash

      ./add_static_routes.sh -o <operation> -m <mode> -s <servers_file> -r <routes_file>
       -o           Operation of the script can be (add, delete ,and print)
       -o add       Add static routes
       -o delete    Delete static routes
       -o print     Only print static routes
       -m           Modify static route can be (offline,online,and all)
       -m offline   Modify static route file
       -m online    Modify memory static route
       -m all       Modify memory static routes and static routes file
       -s           servers file
       -r           static route file which contains all static routes in the format IPv4/CIDER


**Example:**

./add_static_routes.sh -o add -m online -s servers.txt -r routes.txt

This adds static routes to the memory of Linux machine (not permenant) defined in routes.txt to the servers listed in servers.txt.

**Requirements:**

    Linux machine: The script runs on Linux only.
    SSH access: The script requires SSH access to target machines using SSH-keybase authentication.

**Limitations:**

    Currently lacks detailed statistics on added/deleted routes.


**Author:**

Yahya Alshamrani

**Contributing:**

We welcome contributions! Fork the repository on GitHub and submit pull requests with improvements or suggestions.
