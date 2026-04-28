# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'ccs_mrtg class' do
  it_behaves_like 'the example', 'basic.pp'
end
