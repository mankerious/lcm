# encoding: utf-8

require 'gooddata'

module GoodData::Bricks
  class DistributeETLBrick < GoodData::Bricks::Brick
    def version
      '0.0.1'
    end

    def self.transfer_etl(from_project, to_project)
      from_project = case from_project
                       when GoodData::Client
                         from_project.project
                       when GoodData::Segment
                         from_project.master_project
                       else
                         from_project
                       end
    
      to_project = case to_project
                     when GoodData::Client
                       to_project.project
                     when GoodData::Segment
                       to_project.master_project
                     else
                       to_project
                     end

      from_project.processes.each do |process|
        Dir.mktmpdir('etl_transfer') do |dir|
          dir = Pathname(dir)
          filename = dir + 'process.zip'
          File.open(filename, 'w') do |f|
            f << process.download
          end
          to_process = to_project.processes.find { |p| p.name == process.name }
          to_process ? to_process.deploy(filename, type: process.type, name: process.name) : to_project.deploy_process(filename, type: process.type, name: process.name)
        end
      end
      res = (from_project.processes + to_project.processes).map { |p| [p, p.name, p.type]}
      res.group_by { |x| [x[1], x[2]]}
         .select { |_, procs| procs.length == 1}
         .flat_map { |_, procs| procs.select { |p| p[0].project == to_project}.map { |p| p[0] } }
         .peach(&:delete)  
      transfer_schedules(from_project, to_project)
    end

    def self.transfer_schedules(from_project, to_project)
      cache = to_project.processes.sort_by(&:name).zip(from_project.processes.sort_by(&:name)).flat_map {|remote, local| local.schedules.map {|schedule| [remote, local, schedule]}}

      remote_schedules = to_project.schedules
      remote_stuff = remote_schedules.map do |s|
        v = GoodData::Helpers.deep_dup(s).to_hash
        after_schedule = remote_schedules.find { |s2| s.trigger_id == s2.obj_id }
        v[:after] = s.trigger_id && after_schedule && after_schedule.name
        v[:remote_schedule] = s
        v[:params] = v[:params].except("EXECUTABLE", "PROCESS_ID")
        v.compact
      end

      local_schedules = from_project.schedules
      local_stuff = local_schedules.map do |s|
        v = GoodData::Helpers.deep_dup(s).to_hash
        after_schedule = local_schedules.find { |s2| s.trigger_id == s2.obj_id }
        v[:after] = s.trigger_id && after_schedule && after_schedule.name
        v[:remote_schedule] = s
        v[:params] = v[:params].except("EXECUTABLE", "PROCESS_ID")
        v.compact
      end

      diff = GoodData::Helpers.diff(remote_stuff, local_stuff, key: :name, fields: [:name, :cron, :after, :params, :hidden_params, :reschedule])
      stack = diff[:added].map {|x| [:added, x]} + diff[:changed].map {|x| [:changed, x]}
      schedule_cache = remote_schedules.reduce({}) {|a, e| a[e.name] = e; a}
      messages = []
      loop do
        break if stack.empty?
        state, changed_schedule = stack.shift
        if state == :added
          schedule_spec = changed_schedule
          if schedule_spec[:after] && !schedule_cache[schedule_spec[:after]]
            stack << [state, schedule_spec]
            next
          end
          remote_process, process_spec, _ = cache.find {|remote, local, schedule| schedule.name == schedule_spec[:name] }
          messages << { message: "Creating schedule #{schedule_spec[:name]} for process #{remote_process.name}" }
          executable = schedule_spec[:executable] || (process_spec["process_type"] == 'ruby' ? 'main.rb' : 'main.grf')
          created_schedule = remote_process.create_schedule(schedule_spec[:cron] || schedule_cache[schedule_spec[:after]], executable, {
            params: schedule_spec[:params].merge('PROJECT_ID' => to_project.pid),
            hidden_params: schedule_spec[:hidden_params],
            name: schedule_spec[:name],
            reschedule: schedule_spec[:reschedule]
          })
          schedule_cache[created_schedule.name] = created_schedule
        else
          schedule_spec = changed_schedule[:new_obj]
          if schedule_spec[:after] && !schedule_cache[schedule_spec[:after]]
            stack << [state, schedule_spec]
            next
          end
          remote_process, process_spec, _ = cache.find {|i| i[2].name == schedule_spec[:name] }
          schedule = changed_schedule[:old_obj][:remote_schedule]
          messages << { message: "Updating schedule #{schedule_spec[:name]} for process #{remote_process.name}" }
          schedule.params = (schedule_spec[:params] || {}).merge({
            "PROCESS_ID" => remote_process.obj_id
          })
          schedule.cron = schedule_spec[:cron] if schedule_spec[:cron]
          schedule.after = schedule_cache[schedule_spec[:after]] if schedule_spec[:after]
          schedule.hidden_params = schedule_spec[:hidden_params] || {}
          schedule.executable = schedule_spec[:executable] || (process_spec["process_type"] == 'ruby' ? 'main.rb' : 'main.grf')
          schedule.reschedule = schedule_spec[:reschedule]
          schedule.name = schedule_spec[:name]
          schedule.save
          schedule_cache[schedule.name] = schedule
        end
      end

      diff[:removed].each do |removed_schedule|
        messages << { message: "Removing schedule #{removed_schedule[:name]}" }
        removed_schedule[:remote_schedule].delete
      end
      messages
      # messages.map {|m| m.merge({custom_project_id: custom_project_id})}
    end


    def call(params)
      # Connect to GD
      client = params['GDC_GD_CLIENT'] || fail('client needs to be passed into a brick as "GDC_GD_CLIENT"')

      # Get domain name
      domain_name = params['organization'] || params['domain'] || fail('No "organization" or "domain" specified')

      # Lookup for domain by name
      domain = client.domain(domain_name) || fail('Invalid "organization" or "domain" specified')

      # Check if segment (names) were specified
      segment_names = params['segments'] || params['segment_names'] || :all

      # Get segments
      segments = Array(domain.segments(segment_names))

      # Run synchronization
      segments.pmap do |segment|
        segment.clients.each do |client|
          p = client.project
          if p
            puts "Synchronizing #{client.id} (#{p.pid}) with #{segment.id} (#{segment.master_project.pid})"
            DistributeETLBrick.transfer_etl(segment, client)
          end
        end
      end
    end
  end
end
