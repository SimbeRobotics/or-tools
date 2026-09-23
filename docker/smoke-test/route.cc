// -----------------------------------------------------------------------------
// docker/smoke-test/route.cc
// -----------------------------------------------------------------------------
// Solves a four-city TSP with the routing library, which is what the route
// solver uses. Built into a shared library because that's the case where
// leaked symbols matter: a .so exports everything with default visibility,
// whereas an executable only exports what its own shared deps ask for.
// -----------------------------------------------------------------------------
// Copyright (c) 2026, Simbe Robotics, Inc.
// -----------------------------------------------------------------------------
#include <cstdint>
#include <iostream>
#include <vector>

#include "ortools/constraint_solver/routing.h"
#include "ortools/constraint_solver/routing_index_manager.h"
#include "ortools/constraint_solver/routing_parameters.h"

__attribute__((visibility("default"))) int RunSmokeTest() {
  using operations_research::Assignment;
  using operations_research::DefaultRoutingSearchParameters;
  using operations_research::RoutingIndexManager;
  using operations_research::RoutingModel;

  const std::vector<std::vector<int64_t>> distance = {
      {0, 2, 9, 10},
      {1, 0, 6, 4},
      {15, 7, 0, 8},
      {6, 3, 12, 0},
  };

  RoutingIndexManager manager(static_cast<int>(distance.size()), 1,
                              RoutingIndexManager::NodeIndex{0});
  RoutingModel routing(manager);
  const int transit = routing.RegisterTransitCallback(
      [&](int64_t from, int64_t to) -> int64_t {
        return distance[manager.IndexToNode(from).value()]
                       [manager.IndexToNode(to).value()];
      });
  routing.SetArcCostEvaluatorOfAllVehicles(transit);

  const Assignment* solution =
      routing.SolveWithParameters(DefaultRoutingSearchParameters());
  if (solution == nullptr) {
    std::cerr << "smoke test: routing returned no solution\n";
    return 1;
  }
  std::cout << "smoke test: route cost " << solution->ObjectiveValue() << "\n";
  return 0;
}
