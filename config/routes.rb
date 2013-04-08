RedmineApp::Application.routes.draw do
  resources :version_burndown_charts, :only => :index do
    collection do
      get "get_graph_data"
    end
  end
end
