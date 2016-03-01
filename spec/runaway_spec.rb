require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'tempfile'

describe "Runaway" do
  
  it 'supports all the options' do
    require 'logger'
    Runaway.spin(must_quit_within: 2, heartbeat_interval: 0.3, logger: Logger.new($stdout)) {} # just do nothing
  end
  
  context 'with a process that quits cleanly' do
    it 'executes the block' do
      tf = Tempfile.new('signal')
      Runaway.spin { sleep(3); tf << 'written' }
      tf.rewind
      expect(tf.read).to eq('written')
    end
  end
  
  context 'with a process that exceeds the maximum runtime' do
    it 'terminates the process' do
      start_at = Time.now
      expect {
        Runaway.spin(must_quit_within: 3) do
          sleep 30
        end
      }.to raise_error {|err|
        expect(err).to be_kind_of(Runaway::RuntimeExceeded)
        expect(err.message).to match(/\d+ did not terminate after \d+ secs \(limited to 3 secs\)/)
        expect(Time.now - start_at).to be < 5 # Ensure it was killed quickly
      }
    end
  end
  
  context 'with a process that exits with a non-0 status' do
    it 'raises an unclean termination error' do
      expect {
        Runaway.spin { exit 1 }
      }.to raise_error {|err|
        expect(err).to be_kind_of(Runaway::UncleanExit)
        expect(err.message).to match(/\d+ exited uncleanly/)
      }
    end
  end
  
  context 'when a process terminates before the first heartbeat has to be dispatched' do
    it 'just returns :done' do
      t = Time.now
      return_token = Runaway.spin(heartbeat_interval: 5) { sleep 0.1 }
      expect(return_token).to eq(:done)
      delta = Time.now - t
      expect(delta).to be < 2
    end
  end
  
  context 'when a process stops responding to heartbeats' do
    it 'kills it quickly and raises an error' do
      t = Time.now
      expect {
        # Delete, then override the USR2 trap so that heartbeats do not get handled at all
        Runaway.spin(heartbeat_interval: 0.8) { trap('USR2', 'DEFAULT'); trap('USR2') {}; sleep 45 }
      }.to raise_error {|err|
        expect(err).to be_kind_of(Runaway::HeartbeatTimeout)
        expect(err.message).to match(/\d+ did not reply to heartbeat after \d+ secs/)
        expect(Time.now - t).to be < 5 # should really ahve killed it fast
      }
    end
  end
end
