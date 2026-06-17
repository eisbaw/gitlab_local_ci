# frozen_string_literal: true

require 'spec_helper'
require 'indifferent_hash'

RSpec.describe IndifferentHash do
  it 'reads with string or symbol' do
    h = described_class.new('a' => 1)
    expect(h['a']).to eq(1)
    expect(h[:a]).to eq(1)
  end

  it 'writes normalize to string' do
    h = described_class.new
    h[:foo] = 'bar'
    expect(h['foo']).to eq('bar')
  end

  it 'supports key?, fetch, merge, each' do
    h = described_class.new(a: 1)
    expect(h.key?(:a)).to be true
    expect(h.key?('a')).to be true
    expect(h.fetch(:a)).to eq(1)
    expect(h.fetch(:missing, 'd')).to eq('d')

    merged = h.merge(b: 2)
    expect(merged['a']).to eq(1)
    expect(merged['b']).to eq(2)

    seen = {}
    h.each { |k, v| seen[k] = v }
    expect(seen).to eq('a' => 1)
  end

  it 'wraps existing IndifferentHash idempotently' do
    h = described_class.new(a: 1)
    expect(described_class.wrap(h)).to equal(h)
  end
end
