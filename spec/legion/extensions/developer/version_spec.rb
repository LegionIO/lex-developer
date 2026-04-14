# frozen_string_literal: true

RSpec.describe 'Legion::Extensions::Developer::VERSION' do
  it 'is defined' do
    expect(Legion::Extensions::Developer::VERSION).not_to be_nil
  end

  it 'is a valid semver string' do
    expect(Legion::Extensions::Developer::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
