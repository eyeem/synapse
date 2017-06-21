require 'spec_helper'
require 'synapse/service_watcher/serf'

describe Synapse::ServiceWatcher::SerfWatcher do
  let(:mock_synapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    mock_synapse
  end
  let(:discovery) { { 'method' => 'serf', 'hosts' => 'somehost','path' => 'some/path' } }
  
  let(:config) do
    {
      'name' => 'test',
      'haproxy' => {},
      'discovery'=> discovery
    }
  end
  
  context 'SerfWatcher' do
    subject { Synapse::ServiceWatcher::SerfWatcher.new(config, mock_synapse) }
    it 'should validate' do
      expect(subject.send(:validate_discovery_opts)).to be_nil
    end
  end
end
             
