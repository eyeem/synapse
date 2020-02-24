require "synapse/service_watcher/base"

require 'thread'

class Synapse::ServiceWatcher
  class SerfWatcher < BaseWatcher

    def initialize(opts = {}, synapse)
      super(opts, synapse)

      @all_backups_except_one = false
      if opts['haproxy']['all_backups_except_one']
        @all_backups_except_one = opts['haproxy']['all_backups_except_one']
      end
    end
    def start
      @serf_members = '/dev/shm/serf_members.json'
      @cycle_delay = 1

      @last_ctime = 0
      @last_discover = 0
      @last_members_raw = ""
      @last_backends_s = ""

      @watcher = Thread.new do
        watch
      end
    end


# There is an edge case here:
# say that there have been several changes in the network in the last seconds,
# such as a massive rejoin after a network partition.
# The software might pick up a file dated from the beginning of the second and
# it might then be updated at the end of the second, and it wouldn't be noticed
# by stat(2) because it only does second timestamps
#
# So I gave it some thought and came up with something: enforce doing a reread
# ten seconds later

    def watch
      until @should_exit
        begin
          if is_it_time_yet?
            if set_backends(discover())
              log.info "serf backends have changed!"
            end
          end
        rescue => e
          log.warn "Error in watcher thread: #{e.inspect}"
          log.warn e.backtrace
        ensure
          sleep_until_next_check()
        end
      end
      log.info "serf watcher exited successfully"
    end

    def sleep_until_next_check()
      sleep(@cycle_delay)
    end

    def is_it_time_yet?
      ctime = File.stat(@serf_members).ctime.to_i
      if ctime > @last_ctime or (@last_discover < ctime + 10 and Time.new.to_i > ctime + 10)
        @last_ctime = ctime
        true
      else
        false
      end
    end

    # find the current backends at the discovery path; sets @backends
    def discover
      log.info "discovering backends for service #{@name}"
      @last_discover = Time.now.to_i

      # PUT A BEGIN HERE?
      members_raw = File.read @serf_members

      # and sort to compare
      new_backends = parse_members_json(@name, members_raw).sort! { |a,b| a.to_s <=> b.to_s }
      new_backends
    end

    def parse_members_json(name, members_raw)
      new_backends = []

      begin
        members = JSON.parse(members_raw)
      rescue Exception => e
        log.info "exception parsing json #{e.inspect}"
        return new_backends
      end

      return new_backends unless members.is_a? Hash

      if members.has_key? 'members'
        members = members['members']
      else
        return new_backends
      end

      return new_backends unless members.is_a? Array

      # Now I do my pretty parsing

      # please note that because of
      # https://github.com/airbnb/smartstack-cookbook/blob/master/recipes/nerve.rb#L71
      # the name won't just be the name you gave but name_port. this allows a same
      # service to be on multiple ports of a same machine.
      members.each do |member|
        next unless member['status'] == 'alive'
        member['tags'].each do |tag,data|
          puts name, tag, data
          if tag =~ /^smart:#{name}(|_[0-9]+)$/
            host,port = data.split ':'

            # Special trick
            # If we have a all_backups_except_one option
            # We use it here
            # It makes every server except the one we specify (typically the current one)
            # be the only one that doesn't have a 'backup' flag in haproxy. Useful for a
            # scenario where we have a lot of slave servers (ie. mysql, sphinx) that have
            # a local copy of data, and we prefer them, but want to fallback to the others
            # in case of a problem

            extra_haproxy_conf = ''

            if @all_backups_except_one
              if host != @all_backups_except_one
                extra_haproxy_conf = 'backup'
              end
            end


            new_backends << {
              'name' => member['name'],
              'host' => host,
              'port' => port,
              'extra_haproxy_conf' => extra_haproxy_conf,
            }
            log.debug "discovered backend #{member['name']} at #{host}:#{port} for service #{name}"
          end
        end
      end
      return new_backends
    end

    private
    #WTF is the use of this??
    def validate_discovery_opts
      raise ArgumentError, "invalid discovery method #{@discovery['method']}" unless @discovery['method'] == 'serf'
    end
  end
end
