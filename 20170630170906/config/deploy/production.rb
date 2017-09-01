set :stage, :production
set :branch, :master

set :deploy_to, "/home/rails/#{fetch(:stage)}"
set :user, 'rails'

role :app, %w{rails@107.170.143.59}
role :web, %w{rails@107.170.143.59}
role :db,  %w{rails@107.170.143.59}

server '107.170.143.59',
  user: 'rails',
  roles: %w{web app}
