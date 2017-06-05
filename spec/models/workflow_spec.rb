require 'rails_helper'

RSpec.describe Workflow, type: :model do
  let(:workflow) { Workflow.new }

  describe '.update_cache' do
    it 'processes unconfigured workflows' do
      described_class.update_cache("id" => 1, "nero_config" => nil)

      expect(Workflow.count).to eq(1)
      expect(Workflow.first.extractors_config).to eq({})
      expect(Workflow.first.reducers_config).to eq({})
      expect(Workflow.first.rules_config).to eq([])
    end

    it 'processes workflows without rules' do
      described_class.update_cache("id" => 1, "nero_config" => {})

      expect(Workflow.count).to eq(1)
      expect(Workflow.first.extractors_config).to eq({})
      expect(Workflow.first.reducers_config).to eq({})
      expect(Workflow.first.rules_config).to eq([])
    end

    it 'processes configured workflows' do
      extractors_config = {"s" => {"type" => "survey", "task_key" => "T0"}}
      reducers_config = {"s" => {"type" => "stats"}}
      rules_config = [
        {
          "if" => ["gte", ["lookup", "s-VHCL"], ["const", 1]],
          "then" => [{"action" => "retire_subject", "reason" => "flagged"}]
        }
      ]
      caesar_config = {"extractors" => extractors_config, "reducers" => reducers_config, "rules" => rules_config}

      described_class.update_cache("id" => 1, "nero_config" => caesar_config)

      expect(Workflow.count).to eq(1)
      expect(Workflow.first.extractors_config).to eq(extractors_config)
      expect(Workflow.first.reducers_config).to eq(reducers_config)
      expect(Workflow.first.rules_config).to eq(rules_config)
    end

    it 'updates when own record is older' do
      workflow = Workflow.create! id: 1, extractors_config: {s: {type: 'survey'}}, updated_at: 1.hour.ago

      timestamp = 10.minutes.ago.change(usec: 0)
      described_class.update_cache("id" => 1, "nero_config" => {}, "updated_at" => timestamp.as_json)

      expect(Workflow.count).to eq(1)
      expect(Workflow.first.extractors_config.keys).to eq([])
      expect(Workflow.first.updated_at).to eq(timestamp)
    end

    it 'skips when own record is newer' do
      workflow = Workflow.create! id: 1, extractors_config: {s: {type: 'survey'}}, updated_at: 1.hour.ago

      described_class.update_cache("id" => 1, "nero_config" => {}, "updated_at" => 2.hours.ago.as_json)

      expect(Workflow.count).to eq(1)
      expect(Workflow.first.extractors_config.keys).to eq(["s"])
    end
  end

  it 'returns a list of extractors' do
    workflow.extractors_config = {
      "s" => {type: "survey", task_key: "T0"}
    }

    expect(workflow.extractors.size).to eq(1)
    expect(workflow.extractors['s']).to be_a(Extractors::SurveyExtractor)
  end

  it 'returns a list of reducers' do
    workflow.reducers_config = {
      "s" => {type: "stats"}
    }

    expect(workflow.reducers.size).to eq(1)
    expect(workflow.reducers['s']).to be_a(Reducers::StatsReducer)
  end

  describe '#rules' do
    it 'returns a rules engine' do
      workflow.rules_config = [{if: [:eq, [:const, 1], [:const, 1]],
                                then: [{action: "retire_subject"}]}]
      expect(workflow.rules).to be_a(Rules::Engine)
      expect(workflow.rules.size).to eq(1)
    end
  end
end
