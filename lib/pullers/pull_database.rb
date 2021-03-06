# Pulls all stats (player and team) from each game


# Require
require 'rubygems'
require 'json'
require 'open-uri'

require 'sinatra/activerecord'
require_relative '../../models/team'
require_relative '../../models/player'
require_relative '../../models/game'
require_relative '../../models/skater_stat'
require_relative '../../models/goalie_stat'
require_relative '../../models/team_stat'

games_played = Game.all_played_games

# Loop through all played games
games_played.each do |game|

	### FILE PREPARATION ######################################################
	
	puts "Analyzing game: #{game.nhl_id}"

	# Get teams from game id
	home_team_id = game.home_team_id
	away_team_id = game.away_team_id
	home_team = Team.find(home_team_id)
	away_team = Team.find(away_team_id)

	# Open playbyplay file 
	stats_file = open("http://live.nhl.com/GameData/20142015/#{game.nhl_id}/PlayByPlay.json")
	stats = JSON.parse(stats_file.read)['data']['game']

	# Open stats file
	gcbx_file = open("http://live.nhl.com/GameData/20142015/#{game.nhl_id}/gc/gcbx.jsonp")
	gcbx = JSON.parse(gcbx_file.read.strip[10..-2])


	### RECORD TEAM STATS #####################################################

	puts "-- Recording team stats"

	# Retrieve home team stats
	home_stats = gcbx['teamStats']['home']
	home_shots = gcbx['shotSummary'].last['shots'][0]['hShotTot']

	# Store home team info in database
	TeamStat.create(team_id: home_team_id, game_id: game.id, winner: game.home_team_score > game.away_team_score, goals: game.home_team_score, shots: home_shots, blocks: home_stats['hBlock'], pim: home_stats['hPIM'], hits: home_stats['hHits'], fow: home_stats['hFOW'], takeaways: home_stats['hTake'], giveaways: home_stats['hGive'], penalties: home_stats['hPP'])

	# Retrieve away team stats
	away_stats = gcbx['teamStats']['away']
	away_shots = gcbx['shotSummary'].last['shots'][0]['aShotTot']

	# Store away team infor in database
	TeamStat.create(team_id: away_team_id, game_id: game.id, winner: game.away_team_score > game.home_team_score, goals: game.away_team_score, shots: away_shots, blocks: away_stats['aBlock'], pim: away_stats['aPIM'], hits: away_stats['aHits'], fow: away_stats['aFOW'], takeaways: away_stats['aTake'], giveaways: away_stats['aGive'], penalties: away_stats['aPP'])


	### GET SKATERS ###########################################################

	puts "-- Retrieving players"

	stats['plays']['play'].each do |play|

		# Get the player id
		player_id = play['pid']

		# Skip this play if the player has been retrieved or doesn't exist
		next if not player_id or Player.find_by(nhl_id: player_id)

		# Also skip penalties with a 3rd man (Goalie penalty)
		next if play['type'] == 'Penalty' and play['pid3']

		# Get the team the player was on
		player_team_id = ((play['teamid'] == home_team.nhl_id) ? home_team_id : away_team_id)

		# Get player information
		player = Player.create(nhl_id: player_id, team_id: player_team_id, name: play['playername'], sweater: play['sweater'], player_type: 'S')
		skater_total = SkaterStatTotal.create(player_id: player.id)
	end


	### GET GOALIES ###########################################################

	puts "-- Retrieving goalies"

	stats['plays']['play'].each do |play|

		# Skip if no goalie information present
		next if play['type'] != 'Shot'

		# Skip if this goalie has already been stored
		next if Player.find_by(nhl_id: play['pid2'])

		# Get the team the goalie was on
		goalie_team_id = ((play['teamid'] == home_team.nhl_id) ? away_team_id : home_team_id)

		# Get the goalie nhl id
		goalie_nhl_id = play['pid2']

		# Create goalie record
		goalie = Player.new(nhl_id: goalie_nhl_id, team_id: goalie_team_id, name: play['p2name'], player_type: 'G')

		# Handle multiple goaltender situation for this game
		goalie_team_name = ((goalie_team_id == home_team_id) ? 'home' : 'away')

		if gcbx['rosters'][goalie_team_name]['goalies'].length > 1

			saves_made = 0

			# Loop through plays again to find last shot against
			stats['plays']['play'].each do |shot|

				# Skip this play if not a shot by the other team or was made in the shootout
				next if shot['type'] != 'Shot' or shot['teamid'] == goalie_team_id or shot['period'] == 5

				# Skip if this shot was made against another goalie
				next if shot['pid2'] != goalie_nhl_id

				# Increment this goalie's saves
				saves_made += 1
			end

			# Loop through goalies to find the correct one
			gcbx['rosters'][goalie_team_name]['goalies'].each do |goalie_record|

				# Find matching goalie to find jersey number
				if goalie_record['sv'] == saves_made

					goalie.sweater = goalie_record['num']
					break
				end
			end
		else
			goalie.sweater = gcbx['rosters'][goalie_team_name]['goalies'].first['num']
		end

		# Save goalie record
		goalie.save
	end


	### GET SKATER AND GOALIE STATS ###########################################

	puts "-- Pulling stats"

	gcbx['rosters'].each do |roster_team|

		# Extrapolate team id
		roster_team_id = roster_team.include?("home") ? home_team_id : away_team_id


		## Retrieve skater stats ####################################

		puts "   -> Skater stats"

		roster_team[1]['skaters'].each do |record|
			
			# Skip if they never played
			next if record['toi'] == "0:00"

			player = Player.find_by(team_id: roster_team_id, sweater: record['num'])

			# Create stats record if the player exists
			if player

				skater_totals = player.skater_totals

				skater_totals.goals += record['g']
				skater_totals.assists += record['a']
				skater_totals.shots += record['sog']
				skater_totals.pim += record['pim']
				skater_totals.pm += record['pm']
				skater_totals.save

				SkaterStat.create(player_id: player.id, game_id: game.id, team_id: player.team.id, goals: record['g'], assists: record['a'], shots: record['sog'], pim: record['pim'], pm: record['pm'], toi: "00:" + record['toi'])
			end
		end


		## Retrieve goalie stats ####################################

		puts "   -> Goalie stats"

		roster_team[1]['goalies'].each do |record|

			# Skip if they never played
			next if record['toi'] == "0:00"

			goalie = Player.find_by(team_id: roster_team_id, sweater: record['num'])

			# Create stats record if the goalie exists
			if goalie

				# Properly determine goalie playing time
				goalie_tois = record['toi'].split(":")
				minutes = goalie_tois[0].to_i
				seconds = goalie_tois[1].to_i

				hours = (minutes >= 60 ? 1 : 0)
				minutes = (minutes >= 60 ? minutes - 60 : minutes)

				goalie_toi = "#{hours}:#{minutes}:#{seconds}"

				# Create record				
				GoalieStat.create(player_id: goalie.id, game_id: game.id, team_id: goalie.team.id, shots_faced: record['sa'], saves: record['sv'], goals_against: record['ga'], toi: goalie_toi)
			end
		end
	end

	puts "\n"
end

puts "Success"
