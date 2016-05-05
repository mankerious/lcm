# utf-8

require 'open-uri'
require 'csv'
require 'gooddata'

module GoodData
  module Bricks
    class SegmentAssociationBrick < GoodData::Bricks::Brick
      MODES = %w(add_to_organization sync_project sync_domain_and_project sync_multiple_projects_based_on_pid sync_one_project_based_on_pid sync_one_project_based_on_custom_id)

      def version
        '0.0.1'
      end

      def call(params)
        client = params['GDC_GD_CLIENT'] || fail('client needs to be passed into a brick as "GDC_GD_CLIENT"')
        domain_name = params['organization'] || params['domain']
        fail 'organization has to be defined' unless domain_name

        fail 'input_source has to be defined' unless params['input_source']
        data_source = GoodData::Helpers::DataSource.new(params['input_source'])

        domain = client.domain(domain_name)

        client_id_column    = params['client_id_column'] || 'client_id'
        segment_id_column   = params['segment_id_column'] || 'segment_id'
        project_id_column   = params['project_id_column'] || 'project_id'

        clients = []
        CSV.foreach(File.open(data_source.realize(params), 'r:UTF-8'), :headers => true, :return_headers => false, encoding: 'utf-8') do |row|
          clients << {
            :id => row[client_id_column],
            :segment => row[segment_id_column]
          }.compact
        end

        if params.key?('technical_client')
          technical_associtaions = [params['technical_client']].flatten(1)
          technical_associtaions.each do |ta|
            tas = GoodData::Helpers.symbolize_keys(ta)
            clients << { :id => tas[:client_id], :segment => tas[:segment_id] }
          end    
        end

        clients.each do |c|
          fail "Row does not contain client or segment information. Please fill it in or provide custom header information." if c[:segment].blank? || c[:id].blank?
        end

        results = domain.update_clients(clients, delete_extra: true)
        results.group_by { |r| r[:status]}.each do |status, items|
          puts "There were #{items.count} segments #{status.downcase}"
        end
      end
    end
  end
end
