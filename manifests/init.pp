## The handling of snmp_community is horrible. :(

class ccs_mrtg {

  ensure_packages(['net-snmp', 'mrtg', 'pwgen', 'patch', 'freeipmi'])

  ## Get the community from snmpd.conf, or generate a new random one.
  $snmp_community = $facts['snmp_community']

  $snmp_conf = '/etc/snmp/snmpd.conf'


  ## Yuck. TODO just install the whole file in the normal puppet way.
  $snmp_patch = '/tmp/.snmpd.conf.diff'
  file { $snmp_patch:
    ensure => present,
    mode   => '0600',
    source => "puppet:///modules/${title}/snmpd.conf.diff",
  }

  exec { 'snmpd.conf patch':
    unless  => "grep -q lsstROgroup ${snmp_conf}",
    path    => ['/usr/bin'],
    command => "sh -c 'patch -p0 -b -z.ORIG -d / < ${snmp_patch}'",
    notify  => Service['snmpd'],
  }

  file_line { 'snmpd.conf com2sec':
    path   => $snmp_conf,
    line   => "com2sec  local       localhost         ${snmp_community}",
    match  => '^com2sec *local *',
    notify => Service['snmpd'],
  }


  service { 'snmpd':
    ensure => running,
    enable => true,
  }


  $mrtg_user = 'mrtg'
  $mrtg_group = $mrtg_user

  user { $mrtg_user:
    ensure     => present,
    comment    => 'MRTG logging account',
    managehome => true,
  }


  ## TODO do not assume this
  $mrtg_home = '/home/mrtg'

  $mrtg_dir = "${mrtg_home}/mrtg"
  $mrtg_cfg = "${mrtg_dir}/mrtg.cfg"
  $mrtg_lock = "${mrtg_dir}/mrtg.lock"
  $mrtg_pid = "${mrtg_dir}/mrtg.pid"
  $mrtg_log = "${mrtg_dir}/mrtg.log"
  $mrtg_ok = "${mrtg_dir}/mrtg.ok"
  $mrtg_sysinfo = "${mrtg_dir}/mrtg_sysinfo.bash"


  ## SELinux
  ## This assumes the selinux class has been loaded.
  if $facts['os']['selinux']['enabled'] {

    ## Not perfect, but to quieten AVCs.
    $contexts = {
      "${mrtg_dir}(/.*)?" => 'mrtg_var_lib_t',
      regsubst($mrtg_cfg, /\./, '\.')     => 'mrtg_etc_t',
      regsubst($mrtg_lock, /\./, '\.')    => 'mrtg_lock_t',
      regsubst($mrtg_log, /\./, '\.')     => 'mrtg_log_t',
      regsubst($mrtg_pid, /\./, '\.')     => 'mrtg_var_run_t',
      regsubst($mrtg_sysinfo, /\./, '\.') => 'bin_t',
    }
    $contexts.each|$key, $value| {
      selinux::fcontext { $key:
        seltype => $value,
      }
    }

    ## To prevent complaints about monitoring free space in /tmp and /var
    $mrtg_module = 'lsst-mrtg'
    selinux::module { $mrtg_module:
      ensure    => 'present',
      source_te => "puppet:///modules/${title}/${mrtg_module}.te",
      builder   => 'simple'
    }
  }                             # SELinux


  ## TODO better to just install the whole thing.
  $service = '/etc/systemd/system/mrtg.service'
  exec { 'Create mrtg.service':
    path    => ['/usr/bin'],
    command => @("CMD"/L),
      sh -c "sed -e '/^\[Service\]/a\\
      User=${mrtg_user}\n\
      Group=${mrtg_group}\n\
      PIDFile=${mrtg_pid}' \
      -e 's|^ExecStart.*|ExecStart=/usr/bin/mrtg --daemon ${mrtg_cfg} \
      --lock-file ${mrtg_lock} --confcache-file ${mrtg_ok} \
      --pid-file ${mrtg_pid} --logging ${mrtg_log}|' \
      /usr/lib/systemd/system/mrtg.service > ${service}"
      | CMD
    creates => $service,
  }


  file { [$mrtg_dir, "${mrtg_dir}/html"]:
    ensure => directory,
    mode   => '0755',
    owner  => $mrtg_user,
    group  => $mrtg_group,
  }

  ['icons', 'images', 'logs'].each |$dir| {
    file { "${mrtg_dir}/html/${dir}":
      ensure => directory,
      mode   => '0755',
      owner  => $mrtg_user,
      group  => $mrtg_group,
    }
  }


  file { $mrtg_sysinfo:
    ensure => present,
    source => "puppet:///modules/${title}/${basename($mrtg_sysinfo)}",
    mode   => '0755',
    owner  => $mrtg_user,
    group  => $mrtg_group,
  }


  $cfgfile = "${mrtg_dir}/eth.cfg"
  ## To restrict to "main" interface, eg: -if-filter='($if_ip =~ /^134/)'
  ## This is chatty on stderr.
  exec {"Create ${cfgfile}":
    path    => ['usr/sbin', '/usr/bin'],
    command => "cfgmaker --output=${cfgfile} -ifref=ip ${snmp_community}@localhost",
    creates => $cfgfile,
    umask   => '0066',
    user    => 'root',
  }


  $iface_name = $profile::ccs::facts::main_interface

  $iface_info = $facts['networking']['interfaces'][$iface_name]

  if $iface_info {
    $iface_ip = pick($iface_info['ip'], '127.0.0.1')
  } else {
    $iface_ip = '127.0.0.1'
  }

  ## NB this uses $cfgfile.
  $ikey = "netspeed_${iface_ip}"
  $iface_max1 = pick($facts[$ikey], '0')
  ## Default to Gb.
  if $iface_max1 == '0' {
    $iface_max = '125000000'
  } else {
    $iface_max = $iface_max1
  }


  if $profile::ccs::facts::daq {
    $daq_iface_name = $profile::ccs::facts::daq_interface

    ## TODO this duplicates the previous section; abstract it.
    $daq_iface_info = $facts['networking']['interfaces'][$daq_iface_name]

    if $daq_iface_info {
      $daq_iface_ip = pick($daq_iface_info['ip'], '127.0.0.1')
    } else {
      $daq_iface_ip = '127.0.0.1'
    }

    $daq_ikey = "netspeed_${daq_iface_ip}"
    $daq_iface_max1 = pick($facts[$daq_ikey], '0')
    if $daq_iface_max1 == '0' {
      $daq_iface_max = '125000000'
    } else {
      $daq_iface_max = $daq_iface_max1
    }
  } else {
    $daq_iface_name = ''
    $daq_iface_ip = ''
    $daq_iface_max = ''
  }


  $mem_max = $facts['memory']['system']['total_bytes']
  $swap_max = $facts['memory']['swap']['total_bytes']

  ## Eg replace sda with vda for virtual machines.
  if $facts['disks']['sda'] {
    $sda = 'sda'
  } else {
    ## TODO yuck.
    $sda1 = split($facts['mountpoints']['/boot']['device'],/\//)[-1]
    $sda = regsubst($sda1, '\d+$', '')
  }


  ## Find mounted disks.
  $disks = ['/',
            '/home',
            '/var',
            '/tmp',
            '/scratch',
            '/data'].filter |$disk| { $facts['mountpoints'][$disk] }

  $disks_facts = $disks.map |$disk| {
    $name = $disk == '/' ? { true => 'root', default => $disk[1,-1] }
    [ $disk,
      $name,
      $facts['mountpoints'][$disk]['size_bytes'],
      $facts["inodes_${name}"],
    ]
  }

  $temp_ipmi = lookup('ccs_monit::temp', Boolean, undef, false)

  file { $mrtg_cfg:
    ensure  => file,
    owner   => $mrtg_user,
    notify  => Service['mrtg'],
    content => epp(
      "${title}/${basename($mrtg_cfg)}",
      {
        'mrtg_dir'       => $mrtg_dir,
        'hostname'       => $::hostname,
        'snmp_community' => $snmp_community,
        'iface_ip'       => $iface_ip,
        'iface_name'     => $iface_name,
        'iface_max'      => $iface_max,
        'mem_max'        => $mem_max,
        'swap_max'       => $swap_max,
        'sda'            => $sda,
        'disks'          => $disks_facts,
        'temp_ipmi'      => $temp_ipmi,
        'daq_iface_ip'   => $daq_iface_ip,
        'daq_iface_name' => $daq_iface_name,
        'daq_iface_max'  => $daq_iface_max,
      }),
  }


  $htmlfile = "${mrtg_dir}/index.html"

  exec {"Create ${htmlfile}":
    path      => ['usr/sbin', '/usr/bin'],
    command   => @("CMD"/L),
      indexmaker --enumerate --compact --nolegend --prefix=html \
      --title='MRTG Index Page for ${::hostname}' \
      --pageend='<p>Back to <a href="../index.html">index</a>' \
      ${mrtg_cfg} --output ${htmlfile}
      | CMD
    creates   => $htmlfile,
    user      => $mrtg_user,
    subscribe => File[$mrtg_cfg],
  }


  if $facts['os']['selinux']['enabled'] {
    selinux::exec_restorecon { $mrtg_dir:
      recurse => true,
    }
  }


  service { 'mrtg':
    ensure => running,
    enable => true,
  }


}
