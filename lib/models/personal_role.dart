/// Ruolo dopo il login email/password. Lo staff ha `employees/{uid}`; gli altri sono clienti.
enum PersonalRole { customer, staff }

PersonalRole resolvePersonalRole({required bool employeeExists, required bool attivo}) {
  if (!employeeExists) return PersonalRole.customer;
  if (!attivo) throw StateError('Account disattivato');
  return PersonalRole.staff;
}
