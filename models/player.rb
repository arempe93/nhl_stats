# == Schema Information
#
# Table name: players
#
#  id          :integer          not null, primary key
#  nhl_id      :integer
#  team_id     :integer
#  name        :string(255)
#  sweater     :integer
#  player_type :string(255)
#

class Player < ActiveRecord::Base

	# Callbacks

	# Valiadations
	validates :nhl_id, presence: true, uniqueness: true
	validates :team_id, presence: true
	validates :name, presence: true

	# Relationships
	belongs_to :team

	# Functions
end