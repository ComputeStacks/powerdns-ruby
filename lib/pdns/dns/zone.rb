##
# PowerDNS Zone
#
module Pdns::Dns
  class Zone

    attr_accessor :id,
                  :name,
                  :records,
                  :dnssec,
                  :account_id,
                  :features,
                  :updated_at,
                  :created_at

    def initialize(client, id, data = {})
      @client = client
      if self.id
        self.id = "#{self.id}." if self.id.strip.split('').last != '.'
      else
        self.id = nil
        self.name = nil
      end
      self.id = id
      self.records = []
      if data.empty?
        self.dnssec = false
        self.features = {}
      else
        self.dnssec = data['dnssec']
        self.features = {
          'account' => data['account'],
          'kind' => data['kind'],
          'masters' => data['masters']
        }
      end
      load!(data) unless id.nil?
    end

    def load!(data)
      data = data.empty? ? @client.exec!('get', "zones/#{self.id}") : data
      self.dnssec = data['dnssec']
      self.records = process_records!(data) unless data['rrsets'].nil?
    end

    def zone
      # ?
    end

    # View DNSec Params
    def dnssec
      return nil unless self.dnssec
      response = @client.exec!('get', "zones/#{self.id}/cryptokeys")
      data = response.first
      return nil unless data['active']
      key_params = data['ds'].first.split(' ')
      sha256_key = nil
      data['ds'].each do |i|
        p = i.split(' ')
        if p[2] == '3'
          sha256_key = p[3]
          break
        end
      end
      return nil if sha256_key.nil?
      {
        'tag' => key_params[0],
        'alg' => 3,
        'sha256' => sha256_key
      }
    end

    def save
      begin
        self.id.nil? ? create! : update!
      rescue => e
        e.to_s
      else
        self
      end
    end

    def update!
      update_data = {'rrsets' => []}
      current_records = ungrouped_records
      # Load /current/ data to compare
      existing_data = @client.exec!('get', "zones/#{self.id}")
      existing_data['rrsets'].each do |rset|
        update_record = {
          'name' => rset['name'],
          'type' => rset['type'],
          'ttl' => rset['ttl'],
          'changetype' => 'REPLACE',
          'records' => []
        }
        current_records.each do |i|
          if i.type == rset['type'] && i.name == rset['name']
            update_record['ttl'] = i.ttl
            update_record['records'] << {'content' => i.raw_value, 'disabled' => false}
          end
        end
        if update_record['records'].empty?
          update_data['rrsets'] << {
            'name' => rset['name'],
            'type' => rset['type'],
            'changetype' => 'DELETE'
          }
        else
          update_data['rrsets'] << update_record
        end
      end # End existing_data['rrsets'].each
      # Look for new record sets
      new_records = []
      current_records.each do |i|
        is_new = true
        update_data['rrsets'].each do |ii|
          if ii['name'] == i.name && ii['type'] == i.type
            is_new = false
          end
        end
        new_records << [i.name, i.type] if is_new
      end
      new_records.each do |record, type|
        update_record = {
          'name' => record,
          'type' => type,
          'ttl' => 3600,
          'changetype' => 'REPLACE',
          'records' => []
        }
        current_records.each do |i|
          if i.type == type && i.name == record
            update_record['ttl'] = i.ttl
            update_record['records'] << {'content' => i.raw_value, 'disabled' => false}
          end
        end
        unless update_record['records'].empty?
          update_data['rrsets'] << update_record
        end
      end
      @client.exec!('put', "zones/#{self.id}", update_data)
    end

    def create!
      if self.name.strip.split('').last != '.'
        self.name = "#{self.name}."
      end
      data = {
        'name' => self.name,
        'kind' => Pdns.config[:zone_type] == 'Native' ? 'Native' : 'Master',
        'masters' => Pdns.config[:masters],
        'nameservers' => Pdns.config[:nameservers]
      }
      result = @client.exec!('post', 'zones', data)
      self.id = result['id']
      self.load!(result)
      self
      ##
      # Possible use-case for the future, but right now we're useing `allow-axfr-ips` in the master config.
      #
      # Set MetaData to allow AXFR to Slaves
      # https://doc.powerdns.com/md/httpapi/api_spec/#zone-metadata
      # if Pdns.config[:zone_type] == 'Master' && @client.api_version > 4.0 # Currently expected to be supported in v4.1x
      #   metadata = {
      #     'type' => "Metadata",
      #     'kind' => "ALLOW-AXFR-FROM",
      #     'metadata' => ["AUTO-NS"]
      #   }
      #   @client.exec!('post', "zones/#{self.id}/metadata", metadata)
      # end
    end

    def destroy
      begin
        @client.exec!('delete', "zones/#{self.id}")
      rescue
        false
      else
        true
      end
    end

    class << self

      def list_all_zones(client)
        zones_raw = client.exec!('get', 'zones')
        zones = []
        zones_raw.each do |zone|
          zones << Pdns::Dns::Zone.new(client, zone['id'], zone)
        end
        zones
      end

    end

    private

    # Convert 'process_records' to just an array of records
    def ungrouped_records
      val = []
      self.records.each_with_index do |(i,v),k|
        val << v
      end
      val.flatten!
    end

    # Take records and place them into groups for easy rendering client side.
    def process_records!(data)
      records = {
        'SOA' => [],
        'A' => [],
        'AAAA' => [],
        'MX' => [],
        'CNAME' => [],
        'TXT' => [],
        'NS' => [],
        'SRV' => []
      }
      data['rrsets'].each do |i|
        type = i['type']
        ttl = i['ttl']
        name = i['name']
        i['records'].each do |ii|
          record_data = {
            'name' => name,
            'type' => type,
            'ttl' => ttl,
            'content' => ii['content']
          }
          records[type] = [] if records[type].nil?
          records[type] << Pdns::Dns::ZoneRecord.new(nil, nil, nil, record_data)
        end
      end
      self.records = records
    end

  end
end
