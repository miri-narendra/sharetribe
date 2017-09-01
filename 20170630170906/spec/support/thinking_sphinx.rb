# Ensure sphinx directories exist for the test environment
# ThinkingSphinx::Test.init
# Configure and start Sphinx, and automatically
# stop Sphinx at the end of the test suite.
# ThinkingSphinx::Test.start_with_autostop
# This makes tests bit slower, but it's better to use Zeus if wanting to keep sphinx running

# Disable delta indexing as it is not needed and generates unnecessary delay and output
# ThinkingSphinx::Deltas.suspend!


module ThinkingSphinxTestHelpers
  def sphinx_wait_until_index_finished
    sleep 0.25 until sphinx_index_finished?
  end

  def sphinx_ensure_is_running_and_indexed
    begin
      Listing.search("").total_pages
    rescue ThinkingSphinx::ConnectionError
      # Sphinx was not running so start it for this session
      ThinkingSphinx::Test.init
      ThinkingSphinx::Test.start_with_autostop
    end
    ThinkingSphinx::Test.index
    sphinx_wait_until_index_finished
  end

  private

  def sphinx_index_finished?
    Dir[Rails.root.join(ThinkingSphinx::Test.config.indices_location, '*.{new,tmp}.*')].empty?
  end
end

RSpec.configure do |config|
  config.include ThinkingSphinxTestHelpers
end
