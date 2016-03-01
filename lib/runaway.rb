require 'securerandom'

module Runaway
  VERSION = '1.0.1'
  
  UncleanExit = Class.new(StandardError)
  Child = Class.new(StandardError)
  HeartbeatTimeout = Class.new(Child)
  RuntimeExceeded = Class.new(Child)
  
  DEFAULT_HEARTBEAT_INTERVAL = 2
  TERM = 'TERM'.freeze
  KILL = 'KILL'.freeze
  USR2 = 'USR2'.freeze
  DEFAULT = "DEFAULT".freeze
  INF = (1.0 / 0.0)
  
  # Acts as a substitute for a Logger
  module NullLogger; def self.warn(*); end; end
  
  def self.spin(must_quit_within: INF, heartbeat_interval: DEFAULT_HEARTBEAT_INTERVAL, 
    logger: NullLogger, &block_to_run_in_child)
    cookie = SecureRandom.hex(1)
    r, w = IO.pipe
    child_pid = fork do
      r.close_read
      # Remove anything that was there from the parent
      [USR2, TERM, KILL].each { |reset_sig| trap(reset_sig, DEFAULT) }
      
      # When the parent asks us for a heartbeat, send the cookie back
      trap(USR2) { w.write(cookie); w.flush }
      block_to_run_in_child.call
    end
    w.close_write
    
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
    
    last_heartbeat_sent = started_at
    begin
      loop do
        sleep 0.5
        
        break if has_quit
        
        # First check if it has exceeded it's wall clock time allowance
        running_for = Time.now - started_at
        if running_for > must_quit_within
          raise RuntimeExceeded.new('%d did not terminate after %d secs (limited to %d secs)' % [
            child_pid, running_for, must_quit_within])
        end
        
        # Then check if it is time to poke it with a heartbeat
        at = Time.now
        next if (at - last_heartbeat_sent) < heartbeat_interval
        last_heartbeat_sent = at
        
        # Then send it the USR2 as a "ping", and expect a "pong" in
        # the form of a pipe write. If the pipe is still not readable
        # after a certain time, we assume the process has hung.
        Process.kill(USR2, child_pid)
        select_timeout = (heartbeat_interval * 2)
        ready_read = IO.select([r], [], [], select_timeout)
        if ready_read.nil?
          raise HeartbeatTimeout.new('%d did not reply to heartbeat after %d secs' % [child_pid, select_timeout])
        end
        r.read(cookie.bytesize)
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
  ensure
    r.close_read
  end
end
