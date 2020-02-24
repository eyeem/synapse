require 'spec_helper'
require 'synapse/service_watcher/serf'

describe Synapse::ServiceWatcher::SerfWatcher do
  let(:mock_synapse) do
    mock_synapse = instance_double(Synapse::Synapse)
    mockgenerator = Synapse::ConfigGenerator::BaseGenerator.new()
    allow(mock_synapse).to receive(:available_generators).and_return({
      'haproxy' => mockgenerator
    })
    allow(mock_synapse).to receive(:reconfigure!).and_return(true)
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
    context 'watch' do
      it 'should discover new backends' do
        fake_backends = [1,2,3]
        expect(subject).to receive(:discover).and_return(fake_backends)
        expect(subject).to receive(:is_it_time_yet?).and_return(true)
        expect(subject).to receive(:set_backends).with(fake_backends) { subject.stop }
        expect(subject).to receive(:sleep_until_next_check)
        subject.send(:watch)
      end

      it 'sleeps until next check if discover_instances fails' do
        expect(subject).to receive(:is_it_time_yet?).and_return(true)
        expect(subject).to receive(:discover) do
          subject.stop
          raise "discover failed"
        end
        expect(subject).to receive(:sleep_until_next_check)
        subject.send(:watch)
      end
    end

    context 'parse_members_json' do
      it 'should parse json and return backends' do
      members_json = <<-eos
        {
  "members": [
    {
      "name": "ip-10-0-2-7",
      "addr": "10.0.2.7:7946",
      "port": 7946,
      "tags": {
        "smart:espresso-quality-v4_test_9529": "10.0.2.7:9529"
      },
      "status": "alive",
      "protocol": {
        "max": 4,
        "min": 2,
        "version": 4
      }
    },
    {
      "name": "ip-10-0-2-118",
      "addr": "10.0.2.118:7946",
      "port": 7946,
      "tags": {
        "smart:espresso-pa-v1-scores_test_9528": "10.0.2.118:9528"
      },
      "status": "alive",
      "protocol": {
        "max": 4,
        "min": 2,
        "version": 4
      }
    },
    {
      "name": "ip-10-0-2-221",
      "addr": "10.0.2.221:7946",
      "port": 7946,
      "tags": {
        "smart:espresso-coordinator_test_9520": "10.0.2.221:9520"
      },
      "status": "alive",
      "protocol": {
        "max": 4,
        "min": 2,
        "version": 4
      }
    },
    {
      "name": "ip-10-0-2-156",
      "addr": "10.0.2.156:7946",
      "port": 7946,
      "tags": {
        "smart:espresso-captions-v3_test_9525": "10.0.2.156:9525"
      },
      "status": "alive",
      "protocol": {
        "max": 4,
        "min": 2,
        "version": 4
      }
    }
  ]
}
eos
expect(subject.parse_members_json('espresso-coordinator_test', members_json)).to eq [{"name"=>"ip-10-0-2-221","host"=>"10.0.2.221","port"=>"9520","extra_haproxy_conf"=>""}]
expect(subject.parse_members_json('espresso-captions-v3_test', members_json)).to eq [{"name"=>"ip-10-0-2-156","host"=>"10.0.2.156","port"=>"9525","extra_haproxy_conf"=>""}]
expect(subject.parse_members_json('non-existent', members_json)).to eq []
      end
    end
  end
end
