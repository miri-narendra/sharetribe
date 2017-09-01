lock '3.5.0'

set :ssh_options, compression: false, keepalive: true

set :rvm_ruby_version, '2.3.1'
set :application, 'motorhome'
set :repo_url, 'git@git.ithouse.lv:motorhome/motorhome.git'

set :keep_releases, 5

set :whenever_identifier, ->{ "#{fetch(:application)}_#{fetch(:stage)}" }
set :whenever_environment, -> { fetch(:stage) }

# ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }

# set :deploy_to, '/var/www/my_app'
# set :scm, :git

# set :format, :pretty
# set :log_level, :debug
# set :pty, true

set :linked_files, %W{config/database.yml config/config.yml config/#{fetch(:stage)}.sphinx.conf .env #{fetch(:stage)}.env}
set :linked_dirs, %w{log public/system public/assets tmp/cache tmp/pids tmp/binlog db/sphinx}

# set :default_env, { path: '/opt/ruby/bin:$PATH' }
# set :keep_releases, 5

before 'deploy:compile_assets', 'deploy:migrate'

namespace :deploy do

  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      execute :touch, release_path.join('tmp/restart.txt')
    end
  end

  after :restart, :clear_cache do
    on roles(:web), in: :groups, limit: 3, wait: 10 do
      # Here we can do anything such as:
      # within release_path do
      #   execute :rake, 'cache:clear'
      # end
    end
  end

  after :finishing, 'deploy:cleanup'
  after :finished, 'deploy:restart'
end

namespace :foreman do
  desc "Export the Procfile to Ubuntu's upstart scripts"
  task :export do
    on roles(:app) do
      case fetch(:stage)
      when :staging
        within release_path do
          with rails_env: fetch(:stage) do
            execute :sudo, "/usr/local/rvm/bin/rvm #{fetch(:rvm_ruby_version)} do bundle exec foreman export upstart /etc/init " +
          "-f Procfile.#{fetch(:stage)} -a #{fetch(:application)}-#{fetch(:stage)} -u #{fetch(:user)} -l #{shared_path}/log -e ./#{fetch(:stage)}.foreman --root #{current_path} --concurrency worker=1"
          end
        end
      when :production
        within release_path do
          with rails_env: fetch(:stage) do
            execute :sudo, "/usr/local/rvm/bin/rvm #{fetch(:rvm_ruby_version)} do bundle exec foreman export upstart /etc/init " +
            "-f Procfile.#{fetch(:stage)} -a #{fetch(:application)}-#{fetch(:stage)} -u #{fetch(:user)} -l #{shared_path}/log -e ./#{fetch(:stage)}.foreman --root #{current_path} --concurrency worker=1"
          end
        end
      end
    end
  end

  desc 'Start the application services'
  task :start do
    on roles(:app) do
      execute :sudo, "/sbin/start #{fetch(:application)}-#{fetch(:stage)}"
    end
  end

  desc 'Stop the application services'
  task :stop do
    on roles(:app) do
      execute :sudo, "/sbin/stop #{fetch(:application)}-#{fetch(:stage)}"
    end
  end

  desc 'Restart the application services'
  task :restart do
    on roles(:app) do
      execute :sudo, "/sbin/restart #{fetch(:application)}-#{fetch(:stage)}"
    end
  end
end

#namespace :redis do
#  desc 'Symlinks redis dir to shared folder'
#  task :symlink_dir do
#    on roles(:app) do
#      execute :mkdir, " -p #{shared_path}/redis"
#      execute :rm, " -rf #{release_path}/db/redis"
#      execute :ln, " -s #{shared_path}/redis #{release_path}/db/redis"
#    end
#  end
#end

#after 'deploy:symlink:release', 'redis:symlink_dir'
#before 'deploy:updated', 'redis:symlink_dir'

namespace :puma do
  desc 'Symlinks redis dir to shared folder'
  task :sockets_dir do
    on roles(:app) do
      execute :mkdir, " -p #{shared_path}/sockets"
    end
  end
end

before 'deploy:updated', 'puma:sockets_dir'

require './config/boot'

require './config/boot'
#require 'airbrake/capistrano3'

#http://freelancing-gods.com/thinking-sphinx/deployment.html
namespace :sphinx do
  task :stop do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:stage) do
          execute :rake, 'ts:stop'
        end
      end
    end
  end

  task :start do
    on roles(:app) do
      within release_path do
        with rails_env: fetch(:stage) do
          execute :rake, 'ts:start'
        end
      end
    end
  end
end



before 'deploy:updated', 'sphinx:stop'
after  'deploy:finished', 'foreman:restart'

namespace :delayed_job do
  def rails_env
    fetch(:rails_env, false) ? "RAILS_ENV=#{fetch(:rails_env)}" : ''
  end

  def args
    fetch(:delayed_job_args, "")
  end

  def roles
    fetch(:delayed_job_server_role, :app)
  end

  def delayed_job_command
    fetch(:delayed_job_command, "script/delayed_job")
  end

  desc "Stop the delayed_job process"
  task :stop do
    on roles(:app) do
      #run "cd #{current_path};#{rails_env} #{delayed_job_command} stop"
      execute :bash, "-c 'cd #{release_path} && RAILS_ENV=#{fetch(:stage)} /usr/local/rvm/bin/rvm #{fetch(:rvm_ruby_version)} do bundle exec script/delayed_job stop'"
    end
  end

  desc "Start the delayed_job process"
  task :start do
    on roles(:app) do
      execute :bash, "-c 'cd #{release_path} && RAILS_ENV=#{fetch(:stage)} /usr/local/rvm/bin/rvm #{fetch(:rvm_ruby_version)} do bundle exec script/delayed_job start'"
    end
  end

  desc "Restart the delayed_job process"
  task :restart do
    on roles(:app) do
      run "cd #{current_path};#{rails_env} #{delayed_job_command} restart #{args}"
    end
  end
end

after 'deploy:updated',  'delayed_job:stop'
after 'deploy:finished', 'delayed_job:start'

task :generate_stylesheet do
  on roles(:app) do
    within release_path do
      with rails_env: fetch(:stage) do
        execute :rake, 'sharetribe:generate_customization_stylesheets_immediately'
      end
    end
  end
end
after 'deploy:finished', 'generate_stylesheet'
