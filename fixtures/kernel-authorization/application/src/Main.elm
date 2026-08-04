port module Main exposing (main)

import Platform
import Schelm.KernelAuthorizationFixture as SchelmFixture


port report : String -> Cmd msg


main : Program () () Never
main =
    Platform.worker
        { init = \_ ->
            ( ()
            , report (SchelmFixture.value ++ ":elm-core:" ++ String.fromInt (40 + 2))
            )
        , update = never
        , subscriptions = \_ -> Sub.none
        }
