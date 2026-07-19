import { colors } from "../theme/colors";

type Props = { value: string; onChange: (v: string) => void };

function todayISO(): string {
  return new Date().toISOString().slice(0, 10); // AAAA-MM-DD
}

// Web: input nativo de data do navegador (calendário real). `max` = hoje impede
// escolher uma data no futuro. O valor é "AAAA-MM-DD" (mesmo formato usado no
// resto do app).
export default function DateField({ value, onChange }: Props) {
  return (
    <input
      type="date"
      value={value}
      max={todayISO()}
      onChange={(e) => onChange(e.target.value)}
      style={{
        width: "100%",
        boxSizing: "border-box",
        // Alinhado ao ui.input: padding 15/13, raio 8, borda creme translúcida.
        padding: "13px 15px",
        marginTop: 6,
        fontSize: 15,
        borderRadius: 8,
        border: "1px solid rgba(243,236,220,0.16)",
        backgroundColor: colors.card,
        color: colors.ink,
        fontFamily: "inherit",
        colorScheme: "dark",
      }}
    />
  );
}
