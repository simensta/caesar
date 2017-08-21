class ClassificationPipeline
  attr_reader :extractors, :reducers, :rules

  def initialize(extractors, reducers, rules)
    @extractors = extractors
    @reducers = reducers
    @rules = rules
  end

  def process(classification)
    extract(classification)
    reduce(classification.workflow_id, classification.subject_id)
    check_rules(classification.workflow_id, classification.subject_id)
  end

  def extract(classification)
    tries ||= 2

    extractors.each do |key, extractor|
      known_subject = Extract.exists?(subject_id: classification.subject_id, workflow_id: classification.workflow_id)

      data = extractor.process(classification)

      extract = Extract.where(workflow_id: classification.workflow_id, subject_id: classification.subject_id, classification_id: classification.id, extractor_key: key).first_or_initialize
      extract.user_id = classification.user_id
      extract.classification_at = classification.created_at
      extract.data = data
      extract.save!

      unless known_subject
        FetchClassificationsWorker.perform_async(classification.subject_id, classification.workflow_id)
      end

      extract
    end
  rescue ActiveRecord::RecordNotUnique, PG::UniqueViolation
    sleep 2
    retry unless (tries-=1).zero?
    raise
  end

  def reduce(workflow_id, subject_id)
    tries ||= 2

    reducers.each do |key, reducer|
      data = reducer.process(extracts(workflow_id, subject_id))

      reduction = Reduction.where(workflow_id: workflow_id, subject_id: subject_id, reducer_key: key).first_or_initialize
      reduction.data = data
      reduction.save!

      reduction
    end
  rescue ActiveRecord::RecordNotUnique, PG::UniqueViolation
    sleep 2
    retry unless (tries-=1).zero?
    raise
  end

  def check_rules(workflow_id, subject_id)
    return unless rules.present?
    rule_bindings = RuleBindings.new(reductions(workflow_id, subject_id))
    rules.process(workflow_id, subject_id, rule_bindings)
  end

  private

  def extracts(workflow_id, subject_id)
    Extract.where(workflow_id: workflow_id, subject_id: subject_id).order(classification_at: :desc)
  end

  def reductions(workflow_id, subject_id)
    Reduction.where(workflow_id: workflow_id, subject_id: subject_id)
  end
end
