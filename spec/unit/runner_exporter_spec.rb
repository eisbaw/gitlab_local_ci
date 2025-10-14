# frozen_string_literal: true

require 'spec_helper'
require 'runner_exporter'
require 'tmpdir'

RSpec.describe RunnerExporter do
  let(:exporter) { described_class.new }
  let(:mock_client) { double('Gitlab::Client') }
  let(:gitlab_url) { 'https://gitlab.example.com' }
  let(:token) { 'test-token-12345' }

  describe '#export_from_gitlab' do
    let(:mock_runner1) do
      double('Runner',
             id: 1,
             description: 'Test Runner 1',
             active: true,
             tag_list: ['docker', 'linux'],
             run_untagged: false,
             locked: false)
    end

    let(:mock_runner2) do
      double('Runner',
             id: 2,
             description: 'Test Runner 2',
             active: true,
             tag_list: ['shell', 'macos'],
             run_untagged: true,
             locked: false)
    end

    before do
      allow(Gitlab).to receive(:client).and_return(mock_client)
    end

    context 'with valid inputs' do
      it 'validates gitlab_url is not empty' do
        expect {
          exporter.export_from_gitlab('', token, './runners')
        }.to raise_error(ArgumentError, /gitlab_url cannot be nil or empty/)
      end

      it 'validates token is not empty' do
        expect {
          exporter.export_from_gitlab(gitlab_url, '', './runners')
        }.to raise_error(ArgumentError, /token cannot be nil or empty/)
      end

      it 'creates output directory if it does not exist' do
        Dir.mktmpdir do |tmpdir|
          output_dir = File.join(tmpdir, 'new_runners_dir')

          allow(mock_client).to receive(:runners).and_return([])

          exporter.export_from_gitlab(gitlab_url, token, output_dir)

          expect(Dir.exist?(output_dir)).to be true
        end
      end

      it 'exports runners to JSON files' do
        Dir.mktmpdir do |tmpdir|
          allow(mock_client).to receive(:runners).and_return([mock_runner1, mock_runner2])

          count = exporter.export_from_gitlab(gitlab_url, token, tmpdir)

          expect(count).to eq(2)
          expect(File.exist?(File.join(tmpdir, 'runner_1.json'))).to be true
          expect(File.exist?(File.join(tmpdir, 'runner_2.json'))).to be true
        end
      end

      it 'returns zero when no runners found' do
        Dir.mktmpdir do |tmpdir|
          allow(mock_client).to receive(:runners).and_return([])

          count = exporter.export_from_gitlab(gitlab_url, token, tmpdir)

          expect(count).to eq(0)
        end
      end
    end

    context 'with authentication errors' do
      it 'raises AuthenticationError on Unauthorized' do
        # Create a proper mock response object with all required methods
        mock_response = double('Response',
                               code: 401,
                               request: double('Request', base_uri: 'https://gitlab.example.com', path: '/api/v4/runners'),
                               parsed_response: 'Unauthorized',
                               base_uri: 'https://gitlab.example.com')

        allow(mock_client).to receive(:runners).and_raise(Gitlab::Error::Unauthorized.new(mock_response))

        Dir.mktmpdir do |tmpdir|
          expect {
            exporter.export_from_gitlab(gitlab_url, token, tmpdir)
          }.to raise_error(RunnerExporter::AuthenticationError, /Authentication failed/)
        end
      end

      it 'raises AuthenticationError on Forbidden' do
        # Create a proper mock response object with all required methods
        mock_response = double('Response',
                               code: 403,
                               request: double('Request', base_uri: 'https://gitlab.example.com', path: '/api/v4/runners'),
                               parsed_response: 'Forbidden',
                               base_uri: 'https://gitlab.example.com')

        allow(mock_client).to receive(:runners).and_raise(Gitlab::Error::Forbidden.new(mock_response))

        Dir.mktmpdir do |tmpdir|
          expect {
            exporter.export_from_gitlab(gitlab_url, token, tmpdir)
          }.to raise_error(RunnerExporter::AuthenticationError, /Access forbidden/)
        end
      end
    end

    context 'with network errors' do
      it 'raises NetworkError on SocketError' do
        allow(mock_client).to receive(:runners).and_raise(SocketError.new('Failed to resolve host'))

        Dir.mktmpdir do |tmpdir|
          expect {
            exporter.export_from_gitlab(gitlab_url, token, tmpdir)
          }.to raise_error(RunnerExporter::NetworkError, /Network error/)
        end
      end

      it 'raises NetworkError on connection refused' do
        allow(mock_client).to receive(:runners).and_raise(Errno::ECONNREFUSED.new)

        Dir.mktmpdir do |tmpdir|
          expect {
            exporter.export_from_gitlab(gitlab_url, token, tmpdir)
          }.to raise_error(RunnerExporter::NetworkError, /Network error/)
        end
      end
    end
  end

  describe '#format_runner_data' do
    let(:runner) do
      double('Runner',
             id: 123,
             description: 'Docker Runner',
             active: true,
             tag_list: ['docker', 'linux'],
             run_untagged: false,
             locked: false)
    end

    it 'formats runner data correctly' do
      data = exporter.send(:format_runner_data, runner)

      expect(data['id']).to eq('runner_123')
      expect(data['description']).to eq('Docker Runner')
      expect(data['active']).to be true
      expect(data['tags']).to eq(['docker', 'linux'])
      expect(data['run_untagged']).to be false
      expect(data['locked']).to be false
      expect(data['executor']).to be_a(String)
      expect(data['max_jobs']).to eq(1)
    end

    it 'handles missing description' do
      runner_no_desc = double('Runner',
                              id: 456,
                              description: nil,
                              active: true,
                              tag_list: [],
                              run_untagged: false,
                              locked: false)

      data = exporter.send(:format_runner_data, runner_no_desc)

      expect(data['description']).to eq('Runner 456')
    end

    it 'handles optional fields' do
      runner_with_extras = double('Runner',
                                  id: 789,
                                  description: 'Full Runner',
                                  active: true,
                                  tag_list: ['docker'],
                                  run_untagged: false,
                                  locked: false,
                                  access_level: 'not_protected',
                                  maximum_timeout: 3600,
                                  status: 'online',
                                  architecture: 'amd64',
                                  platform: 'linux')

      data = exporter.send(:format_runner_data, runner_with_extras)

      expect(data['access_level']).to eq('not_protected')
      expect(data['maximum_timeout']).to eq(3600)
      expect(data['status']).to eq('online')
      expect(data['architecture']).to eq('amd64')
      expect(data['platform']).to eq('linux')
    end
  end

  describe '#determine_executor' do
    it 'detects docker executor from tags' do
      runner = double('Runner', tag_list: ['docker', 'linux'])
      executor = exporter.send(:determine_executor, runner)
      expect(executor).to eq('docker')
    end

    it 'detects kubernetes executor from tags' do
      runner = double('Runner', tag_list: ['kubernetes', 'cloud'])
      executor = exporter.send(:determine_executor, runner)
      expect(executor).to eq('kubernetes')
    end

    it 'detects kubernetes executor from k8s tag' do
      runner = double('Runner', tag_list: ['k8s'])
      executor = exporter.send(:determine_executor, runner)
      expect(executor).to eq('kubernetes')
    end

    it 'detects shell executor from tags' do
      runner = double('Runner', tag_list: ['shell', 'linux'])
      executor = exporter.send(:determine_executor, runner)
      expect(executor).to eq('shell')
    end

    it 'defaults to shell executor when no specific tags' do
      runner = double('Runner', tag_list: ['linux', 'ruby'])
      executor = exporter.send(:determine_executor, runner)
      expect(executor).to eq('shell')
    end

    it 'handles empty tag list' do
      runner = double('Runner', tag_list: [])
      executor = exporter.send(:determine_executor, runner)
      expect(executor).to eq('shell')
    end

    it 'handles nil tag list' do
      runner = double('Runner', tag_list: nil)
      executor = exporter.send(:determine_executor, runner)
      expect(executor).to eq('shell')
    end
  end

  describe '#fetch_all_runners' do
    before do
      allow(Gitlab).to receive(:client).and_return(mock_client)
      # Initialize client
      exporter.send(:initialize_client, gitlab_url, token)
    end

    it 'fetches runners with pagination' do
      # Simulate two pages of results
      page1_runners = (1..100).map { |i| double('Runner', id: i, description: "Runner #{i}") }
      page2_runners = (101..150).map { |i| double('Runner', id: i, description: "Runner #{i}") }

      expect(mock_client).to receive(:runners).with(page: 1, per_page: 100).and_return(page1_runners)
      expect(mock_client).to receive(:runners).with(page: 2, per_page: 100).and_return(page2_runners)

      runners = exporter.send(:fetch_all_runners)

      expect(runners.count).to eq(150)
    end

    it 'stops pagination when page is not full' do
      # When page 1 returns 50 < 100 runners, pagination stops immediately
      page1_runners = (1..50).map { |i| double('Runner', id: i, description: "Runner #{i}") }

      expect(mock_client).to receive(:runners).with(page: 1, per_page: 100).and_return(page1_runners)
      # Page 2 should NOT be called since page 1 was not full

      runners = exporter.send(:fetch_all_runners)

      expect(runners.count).to eq(50)
    end
  end
end
