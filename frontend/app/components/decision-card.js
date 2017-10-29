import Ember from "ember";

export default Ember.Component.extend({
  classNames: ["decision-card ui card"],
  session: Ember.inject.service("session"),

  actions: {
    respond(response) {
      if (this.get("session.isAuthenticated")) {
        this.get("broadcast").respond(response);
        if (this.get("respondAction")) {
          this.get("respondAction")(this.get("broadcast"));
        } // TODO Remove unnecessary if-clauses: just for testing.
        this.rerender();
      } else {
        if (this.get("loginAction")) {
          this.get("loginAction")();
        } // TODO Remove unnecessary if-clauses: just for testing.
      }
    }
  }
});
