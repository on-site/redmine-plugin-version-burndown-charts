require 'redmine'

Redmine::Plugin.register :redmine_version_burndown do
  name 'Redmine Version Burndown Charts plugin'
  author 'Dai Fujihara'
  description 'Version Burndown Charts Plugin is graphical chart plugin for Scrum.'
  author_url 'http://daipresents.com/weblog/fujihalab/'
  url 'http://daipresents.com/weblog/fujihalab/archives/2010/02/redmine-version-burndown-charts-plugin-release.php '

  requires_redmine :version_or_higher => '2.1.0'
  version '0.0.6'

  project_module :version_burndown_charts do
    permission :version_burndown_charts_view, :version_burndown_charts => :index
  end

  menu :project_menu, :version_burndown_charts, { :controller => 'version_burndown_charts', :action => 'index' },
  :caption => :version_burndown_charts, :after => :activity, :param => :project_id
end

# Registering open flash charts as a plugin with Redmine makes it copy
# the assets into the plugin_assets/open_flash_chart directory so that
# this does not have to be done manually.
Redmine::Plugin.register :open_flash_chart do
  name 'Open Flash Charts plugin'
end
