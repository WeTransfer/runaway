module Runaway
  VERSION = '2.0.0'
  
  UncleanExit = Class.new(StandardError)
  Child = Class.new(StandardError)
  RuntimeExceeded = Class.new(Child)
  
  TERM = 'TERM'.freeze
  KILL = 'KILL'.freeze
  USR2 = 'USR2'.freeze
  DEFAULT = "DEFAULT".freeze
  INF = (1.0 / 0.0)
  
  # Acts as a substitute for a Logger
  module NullLogger; def self.warn(*); end; end
  
  def self.spin(must_quit_within: INF, logger: NullLogger, &block_to_run_in_child)
    child_pid = fork do
      # Remove anything that was there from the parent
      [TERM, KILL].each { |reset_sig| trap(reset_sig, DEFAULT) }
      block_to_run_in_child.call
    end
    
    started_at = Time.now
    
    has_quit = false
    unclean_exit_error = nil
    waiter_t = Thread.new do
      has_quit, status = Process.wait2(child_pid)
      unless status.exitstatus && status.exitstatus.zero?
        unclean_exit_error = UncleanExit.new("#{child_pid} exited uncleanly: #{status.inspect}")
      end
    end
    waiter_t.abort_on_exception = true
    
    soft_signal = ->(sig) {
      (Process.kill(sig, child_pid) rescue Errno::ESRCH) if !has_quit
    }
    
    begin
      loop do
        sleep 1
        
        break if has_quit
        
        # First check if it has exceeded it's wall clock time allowance
        running_for = Time.now - started_at
        if running_for > must_quit_within
          raise RuntimeExceeded.new('%d did not terminate after %d secs (limited to %d secs)' % [
            child_pid, running_for, must_quit_within])
        end
      end
    rescue Runaway => terminating_error
      logger.error "Terminating %d - %s: %s" % [child_pid, terminating_error.class, terminating_error.message]
      soft_signal[TERM]
      sleep 5
      soft_signal[KILL]
      
      raise terminating_error
    rescue Errno::EBADF, Errno::ESRCH, Errno::EPIPE
      # Could not read from the pipe - the child quit, or could not send signal
    end
    
    # If the loop has terminated the process has certainly quit, and we can join the waiter thread
    waiter_t.join
    
    # If the process exited uncleanly (not with status 0) raise an exception in the parent
    raise unclean_exit_error if unclean_exit_error
    
    :done
  end
end
