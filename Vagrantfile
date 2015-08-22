# -*- mode: ruby -*-
# vi: set ft=ruby :

## Need to install dotenv in your vagrant environment
## vagrant plugin install vagrant-dotenv
REQUIRED_PLUGINS = %w(dotenv deep_merge)
exit unless REQUIRED_PLUGINS.all? do |plugin|
  Vagrant.has_plugin?(plugin) || (
  puts "The #{plugin} plugin is required. Please install it with:"
  puts "$ vagrant plugin install #{plugin}"
  false
  )
end

begin
  Dotenv.load
rescue => e
  puts 'problem loading dotenv'
  puts e
  exit 1
end

begin
  require 'deep_merge'
rescue => e
  puts 'problem loading deep_merge'
  puts e
  exit 1
end

require 'yaml'
require 'pathname'
require 'fileutils'

DIR = Pathname.new(__FILE__).dirname

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = '2'

## These environment variables allows the Vagrant Environment to be used to
## prototype any environment at runtime. The same functionality allows
## Vagrant to act as a fixture in an environment (to build containers, act as
## CI containers, and clean-room packaging environment)

VM_BOXES = {
  :ubuntu => 'puppetlabs/ubuntu-14.04-64-puppet',
  :fedora => 'chef/fedora-20',
  :centos => 'puppetlabs/centos-6.5-64-puppet',
}

VM_ENV = ENV['environment'] || 'current_working_directory'
PROVISIONER = ENV['provisioner'] || 'puppet-apply'

module Vagrant
  class Stack
    require 'yaml'
    attr_reader :defaults
    attr_accessor :stack

    def initialize
      @servers = {}
      @defaults = defaults
      @stack = 'default'
    end

    def defaults
      @defaults ||= {
        'memory' => ENV['memory'] || 2048,
        'cpus'   => ENV['cpus'] || 1,
        'puppet' => {
          'facts'  => {
            'role'       => ENV['role'] || 'default',
            'container'  => ENV['container'] || nil,
            'datacenter' => ENV['container'].nil? ? 'vagrant' : 'docker',
          },
        },
        'hostname'  => ENV['hostname'] || 'vagrant',
        'box'       => ENV['box'].nil? ? VM_BOXES[:ubuntu] : VM_BOXES[ENV['box'].to_sym],
        'domain'    => ENV['domain'] || 'stackstorm.net',
        'sync_type' => ENV['sync_type'] || 'rsync',
	      'do'       => {
          'ssh_key_path' => ENV['DO_SSH_KEY_PATH'] || '~/.ssh/id_rsa',
          'token'        => ENV['DO_TOKEN'],
          'image'        => '14.04 x64',
          'region'       => 'nyc3',
          'size'         => '1gb',
        },
        'aws' => {
          'access_key'        => ENV['AWS_ACCESS_KEY'],
          'secret_access_key' => ENV['AWS_SECRET_ACCESS_KEY'],
          'keypair_name'      => ENV['AWS_KEYPAIR_NAME'],
          'ssh_key_path'      => ENV['AWS_SSH_KEY_PATH'] || '~/.ssh/id_rsa',
          'ami'               => ENV['AWS_AMI'] || 'ami-29ebb519',
          'username'          => ENV['AWS_USERNAME'] || 'ubuntu',
          'region'            => ENV['AWS_REGION'] || 'us-west-2',
        },
        'ssh'      => {
          'pty'           => false,
          'forward_agent' => true,
        },
      }
    end

    def servers
      @servers.delete_if {|k, v| k == 'defaults' }
    end

    def add_server(server, config = {})
      @servers[server] = config.deep_merge(defaults)
    end

    def load_stack(stack)
      @stack = ENV['stack'] || 'st2'
      stack_dir = ENV['stack_dir'] || "#{DIR}/stacks"
      stack_file = "#{stack_dir}/#{@stack}.yaml"

      begin
        yaml = YAML::load_file(stack_file)
        yaml.each { |server, config| add_server(server, config) }
      rescue => e
        puts e.message
      end
    end
  end
end

## Load up a pre-defined Stack for development
@stack = Vagrant::Stack.new

unless ENV['stack'].nil?
  @stack.load_stack(ENV['stack'])
else
  ## Defaults for machine. All configurable at runtime as a cleanroom.
  @stack.add_server('default')
end

Vagrant.configure(VAGRANTFILE_API_VERSION) do |vagrant|
  @stack.servers.each do |node, config|
    vagrant.vm.define node do |n|
      n.vm.box            = config['box']
      n.vm.hostname       = "#{config['hostname']}.#{config['domain']}"
      n.ssh.forward_agent = config['ssh']['forward_agent'] || true
      n.ssh.pty           = config['ssh']['pty'] || false

      n.vm.provider 'vmware_fusion' do |vmware|
        vmware.vmx['memsize']  = config['memory'].to_s
        vmware.vmx['numvcpus'] = config['cpus'].to_s
      end

      n.vm.provider 'vmware_workstation' do |vmware|
        vmware.vmx['memsize']  = config['memory'].to_s
        vmware.vmx['numvcpus'] = config['cpus'].to_s
      end

      n.vm.provider 'virtualbox' do |virtualbox|
        virtualbox.memory = config['memory'].to_i
        virtualbox.cpus   = config['cpus'].to_i
      end

      n.vm.provider 'digital_ocean' do |digitalocean, override|
        override.ssh.private_key_path = config['do']['ssh_key_path']
        digitalocean.token            = config['do']['token']
        digitalocean.image            = config['do']['image']
        digitalocean.region           = config['do']['region']
        digitalocean.size             = config['do']['size']
      end

      n.vm.provider 'aws' do |aws, override|
        override.vm.box       = 'dummy'
        aws.region            = config['aws']['region']
        aws.access_key_id     = config['aws']['access_key']
        aws.secret_access_key = config['aws']['secret_access_key']
        aws.keypair_name      = config['aws']['keypair_name']
        aws.ami               = config['aws']['ami']

        override.ssh.username = config['aws']['username']
        override.ssh.private_key_path = config['aws']['ssh_key_path']
      end


      if config.has_key?('private_networks')
        config['private_networks'].each do |nic|
          n.vm.network 'private_network', ip: nic
        end
      end

      # Sync up any file mounts for you
      if config.has_key?('mounts')
        config['mounts'].each do |mount|
          vm_mount, local_mount = mount.split(/:/)
          local_mount ||= [DIR, 'mounts', vm_mount.gsub(/\//, '_')].join('/')
          FileUtils.mkdir_p local_mount
          n.vm.synced_folder local_mount, vm_mount, type: config['sync_type']
        end
      end

      ## Bootstrap using different provisioners.
      case PROVISIONER
      when 'puppet-apply' then
        n.vm.synced_folder '.', '/opt/puppet', type: @synced_folder_type
        n.vm.provision 'shell', inline: '/opt/puppet/script/bootstrap-linux'
        n.vm.provision 'shell', inline: <<-EOF
          # Skips the `git pull` step, since you're working out of it directly
          export update_from_upstream=0

          # Use the current branch by default as the envirnment. Override with environment=XXX
          export environment=#{VM_ENV}

          # Do not update Gems/Puppetfile/Environments each run
          export generate_all_environments=0

          # Notify this is a development workspace
          export development=1

          # Pass through Debug Commands
          export debug=#{ENV['debug']}

          # Collect facts for reference within puppet
          #{config['puppet']['facts'].collect { |k,v| "export FACTER_#{k}=#{v}"}.join("\n")}
          export FACTER_stack=#{@stack.stack}
          /opt/puppet/script/puppet-apply

          ST2_PATH=$(which st2)
          ST2_IP=$(facter st2_ip)
          ST2_FQDN=$(facter fqdn)
          if [ -x "${ST2_PATH}" ]; then
            sudo st2 run core.local date &> /dev/null
            ACTIONEXIT=$?
            if [ ! "${ACTIONEXIT}" == 0 ]; then
              echo ""
              echo "OH NOES!"
              echo "Don't worry! Occasionally something goes wrong, and you just have"
              echo "to kick the tires a bit. Try re-provisioning the workroom with"
              echo ""
              echo "vagrant provision st2express"
              echo ""
              echo "If you don't happen to get the "OK" after that, give us a shout!"
              echo "We don't want to leave you hanging! Come find your favorite way to"
              echo "contact us (slack, irc, groups, or just plain ol email) at"
              echo "http://stackstorm.com/contact"
              echo
              exit 2
            else
              echo ""
              echo ""
              echo "███████╗████████╗██████╗      ██████╗ ██╗  ██╗";
              echo "██╔════╝╚══██╔══╝╚════██╗    ██╔═══██╗██║ ██╔╝";
              echo "███████╗   ██║    █████╔╝    ██║   ██║█████╔╝ ";
              echo "╚════██║   ██║   ██╔═══╝     ██║   ██║██╔═██╗ ";
              echo "███████║   ██║   ███████╗    ╚██████╔╝██║  ██╗";
              echo "╚══════╝   ╚═╝   ╚══════╝     ╚═════╝ ╚═╝  ╚═╝";
              echo ""
              echo "  st2 is installed and ready to use."
              echo ""
              echo "First time starting this machine up?"
              echo "Visit https://${ST2_IP}/setup to configure StackStorm"
              echo ""
              echo "Otherwise, head to https://${ST2_FQDN} to access the WebUI"
            fi
          fi
EOF
      when 'ansible-local' then
        n.vm.provision 'shell', inline: '/vagrant/script/bootstrap-ansible'
        n.vm.provision 'shell', inline: <<-EOF
          # Use the current branch by default as the envirnment. Override with environment=XXX
          export environment=#{VM_ENV}

          # Do not update Gems/Puppetfile/Environments each run
          export generate_all_environments=0

          # Notify this is a development workspace
          export development=1

          # Pass through Debug Commands
          export debug=#{ENV['debug']}

          # (Re)initialize the repo
          git init /opt/ansible
          pushd /opt/ansible

          # Add remote
          git remote add origin https://github.com/stackstorm/ansible-st2 2> /dev/null ||
          echo "Remote origin already exists"

          # Try to detach HEAD
          git checkout --detach -q 2> /dev/null &&
          # if HEAD exist, try to make a fast-forward update of master
          echo "Fetching latest changes from master branch..." &&
          (git fetch origin master:master ||
          echo "Fast-forward on master branch is not possible. Please, reset it manually.") &&
          # then attach the HEAD back
          git checkout - -q ||
          # otherwise, it is likely a new repository, so just create a new master branch off origin
          ( git fetch origin; git checkout master )
          # Finally, run playbook locally
          env PYTHONUNBUFFERED=1 ansible-playbook #{config['ansible']['playbook']} -i 'localhost,' --connection=local
          popd
EOF
      else
        puts "Unsupported provisioner: #{PROVISIONER}. Skipping..."
      end
    end
  end
end
