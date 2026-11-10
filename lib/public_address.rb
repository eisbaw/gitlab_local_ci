# frozen_string_literal: true

# Copyright 2025 gitlab_ci_cli
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'ipaddr'
require 'resolv'
require 'socket'

# SSRF guard for every host a CI config chooses (include:remote, component
# hosts, every redirect hop): the address to connect to, after checking that
# all addresses the host resolves to are public. Callers connect to that
# address only (Net::HTTP ipaddr:), so a DNS answer that changes between
# check and connect is never used. Two callers: IncludeProcessor (remote)
# and ExternalResourceCache#download_file (component, project, template).
module PublicAddress
  module_function

  # Address ranges a fetch chosen by the config must not reach: this host, private and
  # shared (CGNAT) networks, link-local (cloud metadata 169.254.169.254),
  # multicast, and ranges reserved for documentation, benchmarks or future
  # use. IPv6 forms that embed an IPv4 address are checked by that address
  # (embedded_ipv4), not listed here.
  NON_PUBLIC_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
    172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16 198.18.0.0/15
    198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
    ::/128 ::1/128 100::/64 2001:db8::/32 fc00::/7 fe80::/10 fec0::/10 ff00::/8
  ].map { |cidr| IPAddr.new(cidr) }.freeze

  # IPv6 prefixes whose low 32 bits are an IPv4 address the packet ends up
  # at: IPv4-mapped (::ffff:a.b.c.d), IPv4-compatible (::a.b.c.d, deprecated)
  # and NAT64 (64:ff9b::a.b.c.d; DNS64 networks synthesize these for every
  # IPv4-only host, so the prefix itself must stay allowed).
  IPV4_EMBEDDING_PREFIXES = %w[::ffff:0:0/96 ::/96 64:ff9b::/96].map { |cidr| IPAddr.new(cidr) }.freeze

  # The address to connect to for hostname, after checking that every
  # address it resolves to is public. Every address, not just the first: the
  # connection may use any of them. A literal IP host is checked as is.
  #
  # @param hostname [String] URI#hostname (IPv6 literal without brackets)
  # @return [String] first resolved address
  # @raise [RuntimeError] no address, or any address not public
  def resolve!(hostname)
    addresses = literal_ip?(hostname) ? [hostname] : Resolv.getaddresses(hostname)
    raise "Cannot resolve hostname '#{hostname}': no address" if addresses.empty?

    blocked = addresses.reject { |address| public_ip?(IPAddr.new(address)) }
    unless blocked.empty?
      raise "Host '#{hostname}' resolves to a non-public address (#{blocked.join(', ')}); " \
            'a host the CI config chooses may only be public'
    end

    addresses.first
  rescue IPAddr::InvalidAddressError => e
    raise "Cannot check address of '#{hostname}': #{e.message}"
  end

  def literal_ip?(hostname)
    IPAddr.new(hostname)
    true
  rescue IPAddr::InvalidAddressError
    false
  end

  # @param ip [IPAddr]
  def public_ip?(ip)
    embedded = embedded_ipv4(ip)
    return public_ip?(embedded) if embedded

    NON_PUBLIC_RANGES.none? { |range| range.family == ip.family && range.include?(ip) }
  end

  # The IPv4 address an IPv6 address embeds (IPV4_EMBEDDING_PREFIXES), or
  # nil. :: and ::1 lie inside ::/96 but are IPv6 unspecified/loopback, not
  # IPv4, and stay with NON_PUBLIC_RANGES.
  def embedded_ipv4(ip)
    return nil unless ip.ipv6? && ip.to_i > 1
    return nil unless IPV4_EMBEDDING_PREFIXES.any? { |prefix| prefix.include?(ip) }

    IPAddr.new(ip.to_i & 0xffff_ffff, Socket::AF_INET)
  end
end
