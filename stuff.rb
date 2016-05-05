LCM_VERSION_KEY = 'GD_LCM_VERSION'
LCM_PROJECT_TYPE_KEY = 'GD_LCM_TYPE'
LCM_SEGMENT_KEY = 'GD_LCM_SEGMENT'

LCM_MASTER_VALUE = 'master'


def create_or_get_segment(domain, segment_name, master, options = {})
  version = options[:version] || '1.0.0'
  segment = domain.segments(segment_name) rescue false ? domain.segments(segment_name) : domain.create_segment(segment_id: segment_name, master_project: master)
  set_master_metadata(master, version, segment_name)
  segment
end

def set_master_metadata(master, version, segment)
 set_lcm_version(master, version, force: true)
 master.set_metadata(LCM_PROJECT_TYPE_KEY, LCM_MASTER_VALUE)
 master.set_metadata(LCM_SEGMENT_KEY, segment)
end

def create_or_get_client(segment, name)
  client = segment.clients.find {|s| s.id == name}
  client ? client : segment.create_client(id: name)
end

def redeploy_or_create_process(project, path, params)
  process = project.processes.find { |p| p.name == params[:name]}
  if process
    process.deploy(path, params)
  else
    project.deploy_process(path, params)
  end
end

def redeploy_or_create_schedule(process, cron, exec, options)
  fail 'schedule has to have a name' unless options.key?(:name)
  schedule = process.schedules.find { |s| s.name == options[:name] }
  if schedule
    schedule.params = options[:params] || {}
    schedule.hidden_params = options[:hidden_params] || {}
    if cron.is_a?(GoodData::Schedule)
      schedule.after = cron
    else
      schedule.cron = cron
    end
    schedule.save
  else
    process.create_schedule(cron, exec, options)
  end
end

def set_lcm_version(project, version, options = {})
  set_version = project.metadata[LCM_VERSION_KEY]
  force = options[:force]
  fail "Version for project #{project.pid} is already set to #{set_version}. It is forbidden to update versions" if set_version && set_version != version && force == false
  project.set_metadata(LCM_VERSION_KEY, version)
end


class Release

  attr_reader :domain, :handles
  
  def initialize(domain)
    @domain = domain
    @handles = []
  end
  
  def with_segment(segment, &block)
    @handles << [@domain.segments(segment), block]
  end

  def with_project(project, &block)
    @handles << [@domain.client.projects(project), block]
  end

end

def sanity_check(domain)
  current_versions = domain.segments.pmap { |p| p.master_project.metadata[LCM_VERSION_KEY] }
  fail "Not all master projects have a version" unless current_versions.compact.length == domain.segments.length
  fail "Not all master projects are on the same version" unless current_versions.uniq.length == 1
end

def release(domain, new_version, options = {}, &block)
  sanity_check(domain)
  current_version = domain.segments.first.master_project.metadata[LCM_VERSION_KEY]
  fail "New verision #{new_version} is not higher than the old version #{current_version}" if Gem::Version.new(current_version) >= Gem::Version.new(new_version)

  new_projects = domain.segments.pmap do |segment|
    project = segment.master_project
    old_version = project.metadata[LCM_VERSION_KEY]
    new_title = project.title.gsub(old_version, new_version)
    new_project = GoodData::Project.clone_with_etl(project, options.merge({title: new_title}))
    # Remove the VERSION tags so if something goes wrong we have no clutter
    new_project.set_metadata(LCM_VERSION_KEY, nil)
    [segment, new_project]
  end


  release = Release.new(domain)
  block.call(release)

  release.handles.each do |seg, b|
    if seg.is_a(GoodData::Project)
      result = b.call(seg)
    else
      result = b.call(seg, new_projects.find { |s, p| seg.id == s.id }.last)
      if result.is_a?(GoodData::Project)
        new_projects.find { |s, p| seg.id == s.id }.last == result
      end
    end
  end

  new_projects.peach do |segment, project|
    segment.master_project = project
    project.set_metadata(LCM_VERSION_KEY, new_version)
    segment.save
  end

  # UPDATE EXISTING PROJECTS
  ##########################
  # TRANSFER ETLs
  domain.segments do |seg|
    seg.clients.peach { |c| c.project && transfer_etl(seg, c.project) }
  end
  # TRANSFER LDMs
  domain.segments do |seg|
    bp = seg.master_project.blueprint
    seg.clients.peach { |c| c.project && c.project.update_from_blueprint(bp) }
  end
  # Sync reports
  domain.synchronize_clients

  puts "All projects migrated to #{new_version}"
end

def revert(domain, old_version, options = {})
  client = domain.client
  
  projects_to_revert = client.projects.pselect do |p|
    p.metadata[LCM_PROJECT_TYPE_KEY] == LCM_MASTER_VALUE
    p.metadata[LCM_VERSION_KEY] == old_version
  end.map do |p|
    [domain.segments(p.metadata[LCM_SEGMENT_KEY]), p]
  end

  projects_to_revert.group_by { |s, p| s }.select { |s, masters| masters.length > 1 }.each do |s, masters|
    fail "segment #{s.id} has more than one master on version #{old_version}. #{masters.map(&:pid).join(', ')}"
  end

  projects_to_revert.peach do |segment, project|
    segment.master_project = project
    segment.save
  end

  # UPDATE EXISTING PROJECTS
  ##########################
  # TRANSFER ETLs
  domain.segments do |seg|
    seg.clients.peach { |c| c.project && transfer_etl(seg, c.project) }
  end
  # TRANSFER LDMs
  domain.segments do |seg|
    bp = seg.master_project.blueprint
    seg.clients.peach { |c| c.project && c.project.update_from_blueprint(bp) }
  end
  # Sync reports
  domain.synchronize_clients

  puts "All projects reverted to #{old_version}"
end