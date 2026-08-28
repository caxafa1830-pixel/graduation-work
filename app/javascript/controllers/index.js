import { application } from "controllers/application"

import SeabassGameController from "controllers/seabass_game_controller"
application.register("seabass-game", SeabassGameController)
