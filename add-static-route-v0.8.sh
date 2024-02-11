#!/bin/bash

# Check for the correct number of arguments
if [[ ${#} -ne 8 ]]; then
  echo
  echo "This binary add static routes to servers"
  echo "Usage: ${0} -o <operation> -m <mode> -s <servers_file> -r <routes_file>"
  echo " -o           Operation of the script can be (add, delete ,and print)"
  echo " -o add       Add static routes"
  echo " -o delete    Delete static routes"
  echo " -o print     Only print static routes"
  echo " -m           Modify static route can be (offline,online,and all)"
  echo " -m offline   Modify static route file"
  echo " -m online    Modify memory static route"
  echo " -m all       Modify memory static routes and static routes file"
  echo " -s           servers file"
  echo " -r           static route file which contains all static routes in the format IPv4/CIDER"
  echo
  exit 1
fi

# Parse arguments
while getopts "o:m:s:r:" opt; do
  case $opt in
    o) operation=${OPTARG} ;;
    m) mode=${OPTARG} ;;
    s) servers_file=${OPTARG} ;;
    r) routes_file=${OPTARG} ;;
    \?) echo "Invalid option: -${OPTARG}" >&2
        exit 1
        ;;
  esac
done

# Validate arguments
if [[ ! ${operation} =~ ^(add|delete|print)$ ]]; then
  echo "Invalid operation: ${operation}"
  exit 1
fi

if [[ ! ${mode} =~ ^(online|offline|all)$ ]]; then
  echo "Invalid mode: ${mode}"
  exit 1
fi

if [[ ! -f ${servers_file} ]]; then
  echo "Servers file not found: ${servers_file}"
  exit 1
fi

if [[ ! -f ${routes_file} ]]; then
  echo "Routes file not found: ${routes_file}"
  exit 1
fi

# Get the IP Address of the host running the script, to be used to find the gateway of the remote server
mgmt_target=$(hostname -I | cut -d' ' -f1)

# Read static routes from the file
readarray -t static_routes < "${routes_file}"

while IFS='' read -r server_ip
do
  ssh -q -o'StrictHostKeyChecking=false' "root@${server_ip}" <<EOF

$(declare -p server_ip)
$(declare -p static_routes)
$(declare -p operation)
$(declare -p mode)
$(declare -p mgmt_target)

# Get the interface name of the IP address used for SSH
interface=\$(ip a s | grep "\${server_ip}/" | awk '{print \$NF}')

# Get the gateway of the interface, this code also works in case of not gateway for the interface
gateway=\$(ip route get \${mgmt_target} | awk '/src/ {print \$3}')

# Get Network Manager state
nm_state=\$(systemctl is-active NetworkManager.service)

if [[ "\${nm_state}" == "active" ]]; then
  # Get static route file using Network Manager
  static_rotue_file=\$(nmcli -f NAME,DEVICE,FILENAME con show | grep \${interface} | awk '{print \$NF}' | sed 's/ifcfg-/route-/')
else
  # Get static route file using manual way
  static_rotue_file=\$(grep -l "DEVICE=\${interface}" /etc/sysconfig/network-scripts/ifcfg-* | sed 's/ifcfg-/route-/')
fi

# Get current timestamp to append it to static route backup
timestamp="\$(date +"%Y-%m-%d_%H-%M-%S")"

# Check if there will be a change to backup the routes
if [[ "\${operation}" =~ ^(add|delete)$ ]]; then  
  # if there will be change to the static route file, then check if file exists, if not create it
  if [[ "\${mode}" =~ ^(all|offline)$  ]]; then
    # Check if static route file is available otherwise create it
    if [[ ! -f "\${static_rotue_file}" ]]; then
      touch "\${static_rotue_file}"
    fi
  fi
  if [[ "\${mode}" == "online" ]]; then
    # Make backup of memory static routes only
    online_route_backup_file="/tmp/online-static-routes-\${timestamp}.bak"
    ip route show > \${online_route_backup_file}
  elif [[ "\${mode}" == "offline" ]]; then
    # Make a copy of static route file at /tmp/
    offline_static_route_backup_file="/tmp/\$(awk -F'/' '{print "offline-"\$NF}' <<< \${static_rotue_file})_\${timestamp}.bak"
    cp "\${static_rotue_file}" "\${offline_static_route_backup_file}"
  else
    # Make backup of memory static routes and static route file
    online_route_backup_file="/tmp/online-static-routes-\${timestamp}.bak"
    ip route show > \${online_route_backup_file}

    # Make a copy of static route file at /tmp/
    offline_static_route_backup_file="/tmp/\$(awk -F'/' '{print "offline-"\$NF}' <<< \${static_rotue_file})_\${timestamp}.bak"
    cp "\${static_rotue_file}" "\${offline_static_route_backup_file}"
  fi
fi

# Online Static Route
if [[ "\${mode}" =~ ^(online|all)$ ]]; then
  for static_route in "\${static_routes[@]}"; do
    if [[ "\${operation}" == "add" ]]; then
      sr="ip route add \${static_route} via \${gateway} dev \${interface}"
      \${sr} &> /dev/null  && succeed_online_route+=("\${static_route}") || failed_online_route+=("\${static_route}")
    elif [[ "\${operation}" == "delete" ]]; then
      sr="ip route del \${static_route} via \${gateway} dev \${interface}"
      \${sr} &> /dev/null && succeed_online_route+=("\${static_route}") || failed_online_route+=("\${static_route}")
    else
      sr="ip route add \${static_route} via \${gateway} dev \${interface}"
      echo "\${sr}"
    fi
  done
fi

# Offline Static Route
if [[ "\${mode}" =~ ^(offline|all)$ ]]; then

  # check if ipcalc is installed otherwise install it
  if ! command -v ipcalc &> /dev/null; then
    yum install -y ipcalc &>/dev/null
  fi  

  # Get the last line in the static route file for the interface
  last_line_in_offline_static_route_file=\$(grep -vE '^$|^#' \${static_rotue_file} | tail -n1)

  # Check the type of static route file the interface is using
  if [[ "\${last_line_in_offline_static_route_file}" =~ = ]]; then
    if [[ "\${operation}" =~ ^(add|print)$ ]]; then

      # Get the index of Last entry in static route file
      index=\$(echo \${last_line_in_offline_static_route_file} | cut -d'=' -f1 | sed -E 's/GATEWAY|ADDRESS|MASK//')
      index=\$((index+1))
    fi

    for static_route in "\${static_routes[@]}"; do
      if [[ \${operation} =~ add ]]; then
        
        # Strip the static route from the CIDER
        sr=\$(cut -d '/' -f1 <<< "\${static_route}")
        # Check if the static route already present in the static route file
        sr_index=\$(grep "=\${sr}$" \${static_rotue_file} |  cut -d'=' -f1 | sed -E 's/GATEWAY|ADDRESS|MASK//')
        
        if [[ -z "\${sr_index}"  ]]; then

          # Add offline static route entries
          echo "ADDRESS\${index}=\${sr}" >> \${static_rotue_file}
          echo "\$(ipcalc -m "\${static_route}" | sed "s/=/\${index}=/")" >> \${static_rotue_file}
          echo "GATEWAY\${index}=\${gateway}" >> \${static_rotue_file}
          index=\$((index+1)) 
        fi

      elif [[ \${operation} =~ delete ]]; then

        # Get the index of route to be delete, then delete by the index
	sr=\$(cut -d '/' -f1 <<< "\${static_route}")
        index_to_be_deleted=\$(grep "=\${sr}$" \${static_rotue_file} |  cut -d'=' -f1 | sed -E 's/GATEWAY|ADDRESS|MASK//')

        # Check if not index_to_be_deleted is empty, empty means the static route not exists
        if [[ ! -z "\${index_to_be_deleted}" ]]; then

          # Delete the linde based on the index
          sed -i -e "/ADDRESS\${index_to_be_deleted}/d" -e "/GATEWAY\${index_to_be_deleted}/d" -e "/NETMASK\${index_to_be_deleted}/d" \${static_rotue_file} 

          cleaning_index=\${index_to_be_deleted}

          # Fix the index in the static route file
          while IFS= read -r  line; do
            fwd_index=\$((cleaning_index+1))
            if [[ \${line} =~ ^(ADDRESS\${fwd_index}|GATEWAY\${fwd_index}|NETMASK\${fwd_index}) ]]; then
              new_index=\${cleaning_index}
              sed -i -e "s/ADDRESS\${fwd_index}/ADDRESS\${new_index}/" -e "s/GATEWAY\${fwd_index}/GATEWAY\${new_index}/" -e "s/NETMASK\${fwd_index}/NETMASK\${new_index}/" \${static_rotue_file}
              cleaning_index=\$((cleaning_index+1))
            fi
          done < <(cat \${static_rotue_file})
        fi

      else

        # Only print the static routes
        sr=\$(cut -d '/' -f1 <<< "\${static_route}")
        echo "ADDRESS\${index}=\${sr}"
        echo "\$(ipcalc -m "\${static_route}" | sed "s/=/\${index}=/")" 
        echo "GATEWAY\${index}=\${gateway}"
        index=\$((index+1)) 
        
      fi
    done
  else
    # Adding static routes offline
    for static_route in "\${static_routes[@]}"; do
      if [[ "\${operation}" == "add" ]]; then
        echo "\${static_route} via \${gateway}" >> \${static_rotue_file}
      elif [[ "\${operation}" == "delete" ]]; then
        deleted_str="\${static_route/\//\/} via \${gateway}"
        sed -i "/\$deleted_str/d" \${static_rotue_file}
      else
        echo "\${static_route} via \${gateway} dev \${interface}" 
     fi
    done  
  fi
fi


echo "\$(hostname | tr '\n' ',')\${server_ip},\${operation},Done!"

EOF
done < ${servers_file}
