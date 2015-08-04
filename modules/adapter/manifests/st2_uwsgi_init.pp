# Definition: adapter::st2_uwsgi_init
#
#  This adapter creates an init script calling UWSGI for
#  a given StackStorm subsystem. This is to disable the
#  default standalone server started by st2ctl, but to
#  keep that script still usable.
#
define adapter::st2_uwsgi_init (
  $subsystem = $name,
) {
  if ! defined(Class['uwsgi']) and ! defined(Class['::st2::profile::server']) {
    fail("[Adapter::St2_uwsgi_init[${name}]: This adapter can only be used in conjunction with 'uwsgi' and 'st2::profile::server")
  }

  if $::osfamily != 'Debian' {
    fail("[Adapter::St2_uwsgi_init[${name}]: This adapter only supports Debian, currently")
  }

  $_subsystem_map = {
    'api'          => 'st2api',
    'st2api'       => 'st2api',
    'auth'         => 'st2auth',
    'st2auth'      => 'st2auth',
    'installer'    => 'st2installer',
    'st2installer' => 'st2installer',
    'mistral'      => 'mistral',
  }
  $_subsystem = $_subsystem_map[$subsystem]

  file { "/etc/init/${_subsystem}.conf":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0444',
    content => template('adapter/st2_uwsgi_init/init.conf.erb'),
    notify  => Service[$_subsystem],
  }

  service { $_subsystem:
    ensure     => running,
    enable     => true,
    hasstatus  => true,
    hasrestart => true,
  }
}
