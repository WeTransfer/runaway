require File.expand_path(File.dirname(__FILE__) + '/spec_helper')
require 'tempfile'

describe "Runaway" do
  
  it 'supports all the options' do
    require 'logger'
    Runaway.spin(must_quit_within: 2, logger: Logger.new($stdout)) {} # just do nothing
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
end
