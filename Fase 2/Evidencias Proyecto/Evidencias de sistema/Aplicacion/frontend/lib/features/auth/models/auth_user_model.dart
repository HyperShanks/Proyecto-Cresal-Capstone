class AuthUserModel {
  final String idUsuario;
  final String rutUsuario;
  final String nombres;
  final String apellidos;
  final String email;
  final int idRol;
  final String nombreRol;
  final int idSucursal;

  const AuthUserModel({
    required this.idUsuario,
    required this.rutUsuario,
    required this.nombres,
    required this.apellidos,
    required this.email,
    required this.idRol,
    required this.nombreRol,
    required this.idSucursal,
  });

  String get nombreCompleto => '$nombres $apellidos'.trim();

  bool get esRecepcion => idRol == 9;
  bool get esBodeguero => idRol == 1;
  bool get esVendedor => idRol == 2 || idRol == 6 || idRol == 7;
  bool get esCaja => idRol == 3;
  bool get esGerente => idRol == 4 || idRol == 8;
  bool get esAdmin => idRol == 5;

  factory AuthUserModel.fromJson(Map<String, dynamic> json) {
    return AuthUserModel(
      idUsuario: (json['id_usuario'] ?? json['idUsuario'] ?? '').toString(),
      rutUsuario: (json['rut_usuario'] ?? json['rutUsuario'] ?? '').toString(),
      nombres: (json['nombres'] ?? '').toString(),
      apellidos: (json['apellidos'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      idRol: json['id_rol'] is int
          ? json['id_rol'] as int
          : int.tryParse((json['id_rol'] ?? json['idRol'] ?? 0).toString()) ?? 0,
      nombreRol: (json['nombre_rol'] ?? json['nombreRol'] ?? '').toString(),
      idSucursal: json['id_sucursal'] is int
          ? json['id_sucursal'] as int
          : int.tryParse((json['id_sucursal'] ?? json['idSucursal'] ?? 1).toString()) ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'id_usuario': idUsuario,
    'rut_usuario': rutUsuario,
    'nombres': nombres,
    'apellidos': apellidos,
    'email': email,
    'id_rol': idRol,
    'nombre_rol': nombreRol,
    'id_sucursal': idSucursal,
  };
}
