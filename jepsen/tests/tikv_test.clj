(ns jepsen.tikv-test
  (:require [clojure.test :refer :all]
            [jepsen.core :as jepsen]
            [jepsen.tests :as tests]))

(defn tikv-test
  [opts]
  (merge tests/noop-test
         {:name "tikv"
          :os debian/os
          :db tikv/db
          :client (tikv/client opts)
          :checker (checker/compose
                    {:perf (checker/perf)
                     :linear (checker/linearizable)})
          :generator (->> (gen/mix [r w cas])
                         (gen/stagger 1)
                         (gen/nemesis
                           (gen/seq (cycle [(gen/sleep 5)
                                          {:type :info, :f :start}
                                          (gen/sleep 5)
                                          {:type :info, :f :stop}])))
                         (gen/time-limit 60))}
         opts))
