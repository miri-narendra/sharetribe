require 'capistrano/setup'
require 'capistrano/deploy'

require 'capistrano/rvm'
require 'capistrano/bundler'
require 'capistrano/rails/assets'
require 'capistrano/rails/migrations'

require 'whenever/capistrano'

#http://freelancing-gods.com/thinking-sphinx/deployment.html
require 'thinking_sphinx/capistrano'

Dir.glob('lib/capistrano/tasks/*.cap').each { |r| import r }
Dir.glob('lib/capistrano/tasks/*.rake').each { |r| import r }
