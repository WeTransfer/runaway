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
  
  context 'with a process that sleeps for too long' do
    it 'terminates the process' do
      expect {
        Runaway.spin(must_quit_within: 3) do
          sleep 4
        end
      }.to raise_error {|err|
        expect(err).to be_kind_of(Runaway::RuntimeExceeded)
        expect(err.message).to match(/\d+ did not terminate after 4 secs \(limited to 3 secs\)/)
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
  
  context 'when a process stops responding to heartbeats' do
    it 'raises an error' do
      expect {
        Runaway.spin { trap('USR2', 'DEFAULT'); trap('USR2') {}; sleep 7 }
      }.to raise_error {|err|
        expect(err).to be_kind_of(Runaway::HeartbeatTimeout)
        expect(err.message).to match(/\d+ did not reply to heartbeat after 4 secs/)
      }
    end
  end
end
