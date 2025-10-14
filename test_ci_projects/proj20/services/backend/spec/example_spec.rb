# Example RSpec test
RSpec.describe 'Backend Tests' do
  it 'performs basic test' do
    expect(1 + 1).to eq(2)
  end

  it 'tests Rails environment' do
    expect(Rails.env).to be_present
  end
end
