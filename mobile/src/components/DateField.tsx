import { useState } from "react";
import { Pressable, Text } from "react-native";
import DateTimePicker from "@react-native-community/datetimepicker";

import { colors } from "../theme/colors";
import { ui } from "../theme/styles";

type Props = { value: string; onChange: (v: string) => void };

// Nativo: abre o calendário do sistema (DateTimePicker). `maximumDate` = hoje
// impede escolher uma data no futuro. Guarda/emite "AAAA-MM-DD".
export default function DateField({ value, onChange }: Props) {
  const [show, setShow] = useState(false);
  const current = value ? new Date(`${value}T12:00:00`) : new Date();

  return (
    <>
      <Pressable
        style={ui.input}
        onPress={() => setShow(true)}
        accessibilityRole="button"
        accessibilityLabel="Escolher data"
      >
        <Text style={{ fontSize: 16, color: value ? colors.ink : colors.placeholder }}>
          {value || "Escolher data"}
        </Text>
      </Pressable>
      {show ? (
        <DateTimePicker
          value={current}
          mode="date"
          maximumDate={new Date()}
          onChange={(_event, picked) => {
            setShow(false);
            if (picked) onChange(picked.toISOString().slice(0, 10));
          }}
        />
      ) : null}
    </>
  );
}
